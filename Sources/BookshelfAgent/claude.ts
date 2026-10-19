import {
	bookServer,
	bookToolActivity,
	claudeBookTools,
	emitBookReading,
} from "./book-tools.js";
import {
	collect,
	jsonLines,
	redact,
	runtimeEnvironment,
	startChild,
	stopChild,
} from "./process.js";
import type { AccountStatus, Emit, Request } from "./types.js";
import { claudeUsage } from "./usage.js";

export async function claudeStatus(
	request: Request,
	signal: AbortSignal,
	emit?: Emit,
): Promise<AccountStatus> {
	if (!request.claudePath)
		return {
			connected: false,
			billing: "none",
			label: "Claude Code 설치 필요",
		};
	const raw = await collect(
		request.claudePath,
		["--safe-mode", "auth", "status", "--json"],
		request.workspace,
		signal,
	);
	const status = JSON.parse(raw);
	const subscription =
		status.loggedIn &&
		status.authMethod === "claude.ai" &&
		status.apiProvider === "firstParty";
	emit?.({
		type: "models",
		models: [
			{ id: "sonnet", label: "Sonnet" },
			{ id: "opus", label: "Opus" },
			{ id: "haiku", label: "Haiku" },
		],
	});
	return {
		connected: Boolean(subscription),
		billing: subscription ? "subscription" : status.loggedIn ? "api" : "none",
		label: subscription
			? `Claude ${status.subscriptionType || "구독"} 연결됨`
			: status.loggedIn
				? "현재 API 연결입니다. 구독 로그인이 필요합니다."
				: "Claude 로그인 필요",
	};
}

export function claudeArguments(
	instructions: string,
	model?: string,
	request?: Request,
): string[] {
	const server = request ? bookServer(request) : undefined;
	return [
		...(model ? ["--model", model] : []),
		...(server
			? [
					"--setting-sources",
					"",
					"--settings",
					JSON.stringify({ disableAllHooks: true }),
					"--mcp-config",
					JSON.stringify({ mcpServers: { bookside: server } }),
					"--allowedTools",
					...claudeBookTools,
				]
			: ["--safe-mode", "--disallowedTools", "mcp__*"]),
		"--restricted",
		"--disable-slash-commands",
		"--print",
		"--output-format",
		"stream-json",
		"--verbose",
		"--include-partial-messages",
		"--no-session-persistence",
		"--tools",
		"",
		"--strict-mcp-config",
		"--permission-mode",
		"dontAsk",
		"--effort",
		"low",
		"--system-prompt",
		instructions,
	];
}

export async function claudeChat(
	request: Request,
	instructions: string,
	prompt: string,
	signal: AbortSignal,
	emit: Emit,
): Promise<string> {
	const status = await claudeStatus(request, signal);
	emit({ type: "status", status });
	if (!status.connected) throw new Error(status.label);
	return new Promise((resolve, reject) => {
		const child = startChild(
			request.claudePath!,
			claudeArguments(instructions, request.model, request),
			request.workspace,
			{
				...runtimeEnvironment(),
				CLAUDE_CODE_DISABLE_CLAUDE_MDS: "1",
				CLAUDE_CODE_DISABLE_AUTO_MEMORY: "1",
				CLAUDE_CODE_DISABLE_ATTACHMENTS: "1",
			},
		);
		let text = "",
			result: string | undefined,
			error: Error | undefined;
		let lastMessage: any;
		const readingCalls = new Map<string, string>();
		const expectedTools = request.reading ? claudeBookTools : [];
		const cancel = () => {
			error = new Error("답변 생성을 중단했습니다.");
			stopChild(child);
		};
		const timer = setTimeout(
			() => {
				error = new Error("답변 시간이 초과됐습니다. 다시 시도할 수 있습니다.");
				stopChild(child);
			},
			request.reading ? 600000 : 150000,
		);
		signal.addEventListener("abort", cancel, { once: true });
		if (signal.aborted) cancel();
		jsonLines(
			child,
			(record) => {
				if (record.type === "system" && record.subtype === "init") {
					const tools = record.tools ?? [];
					if (
						tools.some((name: string) => !expectedTools.includes(name)) ||
						(record.mcp_servers ?? []).some(
							(server: any) => !request.reading || server.name !== "bookside",
						) ||
						(request.reading &&
							expectedTools.some((name) => !tools.includes(name))) ||
						(record.plugins ?? []).some(
							(plugin: any) => plugin.path !== "builtin",
						) ||
						(record.skills ?? []).length
					) {
						error = new Error(
							"학습 전용 실행에 예상하지 않은 도구가 로드되어 중단했습니다.",
						);
						stopChild(child);
					}
					emit({
						type: "isolation",
						tools,
						mcpServers: record.mcp_servers ?? [],
						skills: record.skills ?? [],
					});
				}
				for (const block of record.message?.content ?? []) {
					if (record.type === "assistant" && block.type === "tool_use") {
						if (!expectedTools.includes(block.name)) {
							error = new Error("허용되지 않은 도구 요청을 중단했습니다.");
							stopChild(child);
							return;
						}
						const name = block.name.replace("mcp__bookside__", "");
						readingCalls.set(block.id, name);
						emit({
							type: "activity",
							message: bookToolActivity(name, block.input),
						});
					}
					if (
						record.type === "user" &&
						block.type === "tool_result" &&
						readingCalls.has(block.tool_use_id)
					) {
						if (!block.is_error)
							emitBookReading(
								typeof block.content === "string"
									? [{ type: "text", text: block.content }]
									: block.content,
								request,
								emit,
							);
						readingCalls.delete(block.tool_use_id);
						emit({ type: "activity", message: "" });
					}
				}
				const event = record.type === "stream_event" ? record.event : undefined;
				if (event?.type === "message_start") lastMessage = event.message;
				if (
					event?.type === "message_delta" &&
					lastMessage &&
					typeof event.usage?.output_tokens === "number"
				)
					lastMessage = {
						...lastMessage,
						usage: {
							...lastMessage.usage,
							output_tokens: event.usage.output_tokens,
						},
					};
				if (
					event?.type === "content_block_delta" &&
					event.delta?.type === "text_delta"
				) {
					const delta = event.delta.text;
					text += delta;
					emit({ type: "delta", text: delta });
				}
				if (record.type === "assistant" && record.message?.usage) {
					const previousOutput =
						lastMessage?.id && lastMessage.id === record.message.id
							? (lastMessage.usage?.output_tokens ?? 0)
							: 0;
					lastMessage = {
						...record.message,
						usage: {
							...record.message.usage,
							output_tokens: Math.max(
								previousOutput,
								record.message.usage.output_tokens ?? 0,
							),
						},
					};
				}
				if (record.type === "result") {
					const usage = claudeUsage(record, lastMessage);
					if (usage) emit({ type: "usage", usage });
					if (record.is_error || record.subtype !== "success")
						error = new Error(
							redact(
								(record.errors ?? [record.result ?? "답변 생성 실패"]).join(
									"\n",
								),
							),
						);
					else result = record.result ?? text;
				}
			},
			(failure) => {
				error = failure;
				stopChild(child);
			},
		);
		child.stderr.on("data", () => {
			/* Credentials and verbose diagnostics are never forwarded. */
		});
		child.on("error", (failure) => {
			error = failure;
		});
		child.on("close", (code) => {
			clearTimeout(timer);
			signal.removeEventListener("abort", cancel);
			if (error) reject(error);
			else if (code !== 0 || result === undefined || !result.trim())
				reject(new Error("Claude가 완성된 답변을 반환하지 않았습니다."));
			else resolve(result);
		});
		child.stdin.end(prompt);
	});
}

export async function claudeLogin(
	request: Request,
	signal: AbortSignal,
	emit: Emit,
) {
	if (!request.claudePath) throw new Error("Claude Code를 먼저 설치해 주세요.");
	await new Promise<void>((resolve, reject) => {
		const child = startChild(
			request.claudePath!,
			["--safe-mode", "auth", "login", "--claudeai"],
			request.workspace,
		);
		let latest = "";
		const cancel = () => {
			stopChild(child);
			reject(new Error("로그인을 취소했습니다."));
		};
		const timer = setTimeout(cancel, 240000);
		signal.addEventListener("abort", cancel, { once: true });
		child.stdout.on("data", (chunk) => {
			latest = (latest + String(chunk)).slice(-12000);
			const match = latest.match(
				/https:\/\/(?:claude\.ai|platform\.claude\.com|console\.anthropic\.com)\/[^\s]+/,
			);
			if (match) {
				emit({
					type: "login_url",
					url: match[0].split(String.fromCharCode(27))[0],
					openAutomatically: false,
				});
				latest = "";
			}
		});
		child.stderr.on("data", () => {});
		child.on("error", reject);
		child.on("close", (code) => {
			clearTimeout(timer);
			signal.removeEventListener("abort", cancel);
			code === 0
				? resolve()
				: reject(new Error("Claude 공식 로그인을 완료하지 못했습니다."));
		});
	});
	return claudeStatus(request, signal);
}
