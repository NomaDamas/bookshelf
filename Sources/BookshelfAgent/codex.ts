import { mkdir } from "node:fs/promises";
import {
	jsonLines,
	runtimeEnvironment,
	startChild,
	stopChild,
} from "./process.js";
import type { AccountStatus, Emit, Request } from "./types.js";

export function codexArguments(): string[] {
	return [
		"app-server",
		"--stdio",
		"--disable",
		"shell_tool",
		"--disable",
		"plugins",
		"--disable",
		"apps",
		"--disable",
		"multi_agent",
		"--disable",
		"image_generation",
		"--disable",
		"view_image",
		"--disable",
		"skill_search",
		"--disable",
		"tool_suggest",
		"--disable",
		"sleep_tool",
		"-c",
		'web_search="disabled"',
		"-c",
		"project_doc_max_bytes=0",
		"-c",
		"skills.include_instructions=false",
		"-c",
		"skills.bundled.enabled=false",
		"-c",
		"tools.update_plan.enabled=false",
	];
}

class CodexConnection {
	private child;
	private serial = 0;
	private pending = new Map<
		number,
		{
			resolve: (value: any) => void;
			reject: (error: Error) => void;
			timer: ReturnType<typeof setTimeout>;
		}
	>();
	onEvent: (method: string, params: any) => void = () => {};
	onFailure: (error: Error) => void = () => {};
	constructor(
		private request: Request,
		private signal: AbortSignal,
	) {
		if (!request.codexPath) throw new Error("Codex CLI를 먼저 설치해 주세요.");
		this.child = startChild(
			request.codexPath,
			codexArguments(),
			request.workspace,
			{ ...runtimeEnvironment(), CODEX_HOME: request.codexHome },
		);
		jsonLines(
			this.child,
			(record) => {
				if (record.method && record.id !== undefined) {
					this.send({
						id: record.id,
						error: {
							code: -32601,
							message: "This reading client does not provide this capability.",
						},
					});
				} else if (record.id !== undefined) {
					const request = this.pending.get(record.id);
					if (!request) return;
					clearTimeout(request.timer);
					this.pending.delete(record.id);
					record.error
						? request.reject(
								new Error(record.error.message || "Codex 연결 오류"),
							)
						: request.resolve(record.result);
				} else if (record.method)
					this.onEvent(record.method, record.params ?? {});
			},
			(error) => this.fail(error),
		);
		this.child.stderr.on("data", () => {});
		this.child.on("error", (error) => this.fail(error));
		this.child.on("close", () =>
			this.fail(new Error("Codex 연결이 종료됐습니다.")),
		);
		signal.addEventListener("abort", this.cancel, { once: true });
	}
	private cancel = () => {
		this.fail(new Error("요청을 중단했습니다."));
		this.close();
	};
	private fail(error: Error) {
		for (const pending of this.pending.values()) {
			clearTimeout(pending.timer);
			pending.reject(error);
		}
		this.pending.clear();
		this.onFailure(error);
	}
	private send(value: unknown) {
		if (this.child.stdin.writable)
			this.child.stdin.write(JSON.stringify(value) + "\n");
	}
	call(method: string, params: unknown, timeout = 20000): Promise<any> {
		if (this.signal.aborted)
			return Promise.reject(new Error("요청을 중단했습니다."));
		const id = ++this.serial;
		return new Promise((resolve, reject) => {
			const timer = setTimeout(() => {
				this.pending.delete(id);
				reject(new Error("Codex 연결 시간이 초과됐습니다."));
			}, timeout);
			this.pending.set(id, { resolve, reject, timer });
			this.send({ id, method, params });
		});
	}
	async initialize() {
		await this.call("initialize", {
			clientInfo: {
				name: "bookshelf_pi_preview",
				title: "Bookshelf Pi Preview",
				version: "0.1.0",
			},
		});
		this.send({ method: "initialized", params: {} });
	}
	async status(): Promise<AccountStatus> {
		const result = await this.call("account/read", { refreshToken: false });
		const account = result.account;
		return {
			connected: account?.type === "chatgpt",
			billing:
				account?.type === "chatgpt" ? "subscription" : account ? "api" : "none",
			label:
				account?.type === "chatgpt"
					? `ChatGPT ${account.planType || "구독"} 연결됨`
					: account
						? "현재 API 연결입니다. ChatGPT 로그인이 필요합니다."
						: "ChatGPT 로그인 필요",
		};
	}
	close() {
		this.signal.removeEventListener("abort", this.cancel);
		this.onFailure = () => {};
		stopChild(this.child);
	}
}

async function connection(request: Request, signal: AbortSignal) {
	await mkdir(request.codexHome, { recursive: true, mode: 0o700 });
	const client = new CodexConnection(request, signal);
	try {
		await client.initialize();
		return client;
	} catch (error) {
		client.close();
		throw error;
	}
}

export async function codexStatus(
	request: Request,
	signal: AbortSignal,
): Promise<AccountStatus> {
	if (!request.codexPath)
		return { connected: false, billing: "none", label: "Codex CLI 설치 필요" };
	const client = await connection(request, signal);
	try {
		return await client.status();
	} finally {
		client.close();
	}
}

export async function codexLogin(
	request: Request,
	signal: AbortSignal,
	emit: Emit,
): Promise<AccountStatus> {
	const client = await connection(request, signal);
	let loginID: string | undefined;
	try {
		await new Promise<void>((resolve, reject) => {
			const timer = setTimeout(
				() => reject(new Error("로그인 시간이 초과됐습니다.")),
				240000,
			);
			const finish = (error?: Error) => {
				clearTimeout(timer);
				error ? reject(error) : resolve();
			};
			client.onFailure = finish;
			client.onEvent = (method, params) => {
				if (method === "account/login/completed")
					finish(
						params.success
							? undefined
							: new Error("ChatGPT 로그인을 완료하지 못했습니다."),
					);
			};
			client
				.call("account/login/start", { type: "chatgpt" })
				.then((result) => {
					loginID = result.loginId;
					emit({
						type: "login_url",
						url: result.authUrl,
						openAutomatically: true,
					});
				})
				.catch(finish);
		});
		return await client.status();
	} finally {
		if (signal.aborted && loginID)
			await client
				.call("account/login/cancel", { loginId: loginID }, 1000)
				.catch(() => {});
		client.close();
	}
}

export async function codexChat(
	request: Request,
	instructions: string,
	prompt: string,
	signal: AbortSignal,
	emit: Emit,
): Promise<string> {
	const client = await connection(request, signal);
	try {
		const status = await client.status();
		emit({ type: "status", status });
		if (!status.connected) throw new Error(status.label);
		const models = await client.call("model/list", { includeHidden: false });
		const selected =
			models.data?.find((model: any) => model.isDefault) ?? models.data?.[0];
		if (!selected)
			throw new Error(
				"이 계정에서 사용할 수 있는 Codex 모델을 찾지 못했습니다.",
			);
		const thread = await client.call("thread/start", {
			ephemeral: true,
			modelProvider: "openai",
			model: selected.model ?? selected.id,
			baseInstructions: instructions,
			developerInstructions:
				"Use only the reference text supplied in the user message. Do not invoke tools.",
			cwd: request.workspace,
			sandbox: "read-only",
			approvalPolicy: "never",
		});
		emit({
			type: "isolation",
			profile: "app-owned CODEX_HOME",
			tools: "shell, plugins, apps, multi-agent and web search disabled",
			model: selected.model ?? selected.id,
		});
		return await new Promise<string>((resolve, reject) => {
			let text = "",
				activeTurn: string | undefined;
			const timer = setTimeout(() => {
				client
					.call(
						"turn/interrupt",
						{ threadId: thread.thread.id, turnId: activeTurn },
						1000,
					)
					.catch(() => {});
				reject(new Error("답변 시간이 초과됐습니다."));
			}, 150000);
			const finish = (error?: Error) => {
				clearTimeout(timer);
				error
					? reject(error)
					: text.trim()
						? resolve(text)
						: reject(new Error("Codex가 빈 답변을 반환했습니다."));
			};
			client.onFailure = finish;
			client.onEvent = (method, params) => {
				if (params.threadId && params.threadId !== thread.thread.id) return;
				if (
					method === "item/started" &&
					![
						"agentMessage",
						"reasoning",
						"userMessage",
						"contextCompaction",
					].includes(params.item?.type)
				) {
					finish(
						new Error(
							"학습 전용 연결에서 추가 도구 실행이 요청되어 중단했습니다.",
						),
					);
					client.close();
					return;
				}
				if (method === "item/agentMessage/delta") {
					text += params.delta;
					emit({ type: "delta", text: params.delta });
				}
				if (
					method === "item/completed" &&
					params.item?.type === "agentMessage" &&
					!text
				) {
					text = params.item.text ?? "";
					emit({ type: "delta", text });
				}
				if (method === "turn/completed")
					finish(
						params.turn?.status === "completed"
							? undefined
							: new Error(
									params.turn?.error?.message ?? "Codex 답변이 중단됐습니다.",
								),
					);
			};
			client
				.call("turn/start", {
					threadId: thread.thread.id,
					input: [{ type: "text", text: prompt, text_elements: [] }],
					serviceTierForTurn: "default",
				})
				.then((result) => {
					activeTurn = result.turn?.id;
				})
				.catch(finish);
		});
	} finally {
		client.close();
	}
}
