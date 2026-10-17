import { type ChildProcessWithoutNullStreams, spawn } from "node:child_process";
import { StringDecoder } from "node:string_decoder";

export function runtimeEnvironment(): NodeJS.ProcessEnv {
	const result: NodeJS.ProcessEnv = {};
	// Account credentials stay inside the official executables. Do not inherit an
	// API key or proxy override that could silently change the selected billing mode.
	for (const key of [
		"HOME",
		"USER",
		"LOGNAME",
		"PATH",
		"TMPDIR",
		"LANG",
		"LC_ALL",
		"LC_CTYPE",
		"SHELL",
		"CLAUDE_CONFIG_DIR",
	]) {
		if (process.env[key]) result[key] = process.env[key];
	}
	return result;
}

export function redact(text: string): string {
	return text
		.replace(/sk-[A-Za-z0-9_-]+/g, "[redacted]")
		.replace(/Bearer\s+[^\s"']+/gi, "Bearer [redacted]")
		.replace(/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, "[redacted]")
		.slice(0, 1600);
}

export function startChild(
	command: string,
	args: string[],
	cwd: string,
	env = runtimeEnvironment(),
) {
	return spawn(command, args, {
		cwd,
		env,
		stdio: ["pipe", "pipe", "pipe"],
		detached: true,
	});
}

export function stopChild(child: ChildProcessWithoutNullStreams) {
	if (child.exitCode !== null || child.signalCode !== null) return;
	child.stdin.end();
	try {
		if (child.pid) process.kill(-child.pid, "SIGTERM");
	} catch {
		/* Already exited. */
	}
	const timer = setTimeout(() => {
		if (child.exitCode === null && child.signalCode === null) {
			try {
				if (child.pid) process.kill(-child.pid, "SIGKILL");
			} catch {
				/* Already exited. */
			}
		}
	}, 1500);
	timer.unref();
}

export function jsonLines(
	child: ChildProcessWithoutNullStreams,
	consume: (value: any) => void,
	fail: (error: Error) => void,
) {
	const decoder = new StringDecoder("utf8");
	let buffer = "";
	child.stdout.on("data", (chunk: Buffer) => {
		buffer += decoder.write(chunk);
		if (buffer.length > 2_000_000) {
			fail(new Error("실행기 응답이 너무 큽니다."));
			stopChild(child);
			return;
		}
		for (;;) {
			const index = buffer.indexOf("\n");
			if (index < 0) break;
			const line = buffer.slice(0, index).replace(/\r$/, "");
			buffer = buffer.slice(index + 1);
			if (!line.trim()) continue;
			try {
				consume(JSON.parse(line));
			} catch (error) {
				fail(
					error instanceof Error ? error : new Error("응답을 읽지 못했습니다."),
				);
			}
		}
	});
}

export async function collect(
	command: string,
	args: string[],
	cwd: string,
	signal: AbortSignal,
	timeoutMs = 15000,
): Promise<string> {
	return new Promise((resolve, reject) => {
		if (signal.aborted) {
			reject(new Error("취소했습니다."));
			return;
		}
		const child = startChild(command, args, cwd);
		let output = "",
			errors = "";
		const cancel = () => {
			stopChild(child);
			reject(new Error("취소했습니다."));
		};
		const timer = setTimeout(() => {
			stopChild(child);
			reject(new Error("연결 확인 시간이 초과됐습니다."));
		}, timeoutMs);
		signal.addEventListener("abort", cancel, { once: true });
		child.stdout.on("data", (chunk) => {
			output += chunk;
			if (output.length > 200_000) cancel();
		});
		child.stderr.on("data", (chunk) => {
			errors = (errors + chunk).slice(-4000);
		});
		child.on("error", reject);
		child.on("close", (code) => {
			clearTimeout(timer);
			signal.removeEventListener("abort", cancel);
			if (code === 0) resolve(output);
			else
				reject(
					new Error(redact(errors) || "공식 실행기를 확인하지 못했습니다."),
				);
		});
		child.stdin.end();
	});
}
