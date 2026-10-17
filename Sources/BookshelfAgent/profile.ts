import { copyFile, mkdir, writeFile } from "node:fs/promises";
import { learningInstructions, learningSkills } from "./instructions.js";

await mkdir("../../dist/agent", { recursive: true });
await copyFile("renderer.html", "../../dist/agent/renderer.html");
await writeFile(
	"../../dist/agent/profile.json",
	JSON.stringify(
		{ version: 1, systemPrompt: learningInstructions, skills: learningSkills },
		null,
		2,
	) + "\n",
);
