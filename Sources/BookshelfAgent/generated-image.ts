import { randomUUID } from "node:crypto";
import { lstat, mkdir, writeFile } from "node:fs/promises";
import { isAbsolute, join } from "node:path";

export const maxGeneratedImageBytes = 32 * 1024 * 1024;
export const maxCodexEventBytes = 48 * 1024 * 1024;

/** Accept image bytes from the official event, never a model-supplied savedPath. */
export async function saveGeneratedImage(result: unknown, directory?: string) {
	if (!directory || !isAbsolute(directory))
		throw new Error("이미지 보관 폴더가 없습니다. 앱을 업데이트해 주세요.");
	if (
		typeof result !== "string" ||
		result.length > Math.ceil(maxGeneratedImageBytes / 3) * 4 ||
		!result.length ||
		result.length % 4 !== 0 ||
		!/^[A-Za-z0-9+/]*={0,2}$/.test(result)
	)
		throw new Error("생성된 이미지 데이터를 읽을 수 없습니다.");
	const bytes = Buffer.from(result, "base64");
	if (
		bytes.length > maxGeneratedImageBytes ||
		bytes.length < 33 ||
		!bytes
			.subarray(0, 8)
			.equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10])) ||
		bytes.toString("ascii", 12, 16) !== "IHDR"
	)
		throw new Error("생성된 PNG 이미지를 읽을 수 없습니다.");
	const width = bytes.readUInt32BE(16),
		height = bytes.readUInt32BE(20);
	if (!width || !height || width * height > 40_000_000)
		throw new Error("생성된 이미지 크기가 지원 범위를 벗어났습니다.");
	await mkdir(directory, { recursive: true, mode: 0o700 });
	const root = await lstat(directory);
	if (!root.isDirectory() || root.isSymbolicLink())
		throw new Error("이미지 보관 폴더를 확인해 주세요.");
	const id = randomUUID(),
		fileName = `${id}.png`;
	await writeFile(join(directory, fileName), bytes, {
		mode: 0o600,
		flag: "wx",
	});
	return { id, name: "Codex 생성 이미지", fileName, kind: "image" };
}
