import { copyFile, mkdir, writeFile } from "node:fs/promises";
import {
	bookReadingInstructions,
	learningInstructions,
	learningSkills,
	runtimeInstructions,
} from "./instructions.js";

await mkdir("../../dist/agent", { recursive: true });
await copyFile("renderer.html", "../../dist/agent/renderer.html");
await writeFile(
	"../../dist/agent/profile.json",
	JSON.stringify(
		{
			version: 2,
			defaultSkill: "auto",
			systemPrompt: learningInstructions,
			skills: learningSkills,
			runtimes: runtimeInstructions,
			bookReading: bookReadingInstructions,
		},
		null,
		2,
	) + "\n",
);
