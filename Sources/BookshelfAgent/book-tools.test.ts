import { expect, test } from "bun:test";
import { chmod, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
	bookServer,
	bookToolNames,
	claudeBookTools,
	emitBookReading,
} from "./book-tools.js";
import { claudeArguments } from "./claude.js";
import { codexArguments } from "./codex.js";
import { handle, validateRequest } from "./index.js";
import { systemInstructions } from "./instructions.js";
import type { Request } from "./types.js";
import { claudeUsage } from "./usage.js";

const base: Request = {
	action: "chat",
	backend: "claude",
	usePi: true,
	skill: "auto",
	workspace: "/workspace",
	codexHome: "/codex",
	reading: {
		command: "/Applications/Bookside Pi.app/Contents/MacOS/bookside-cli",
		directory: "/library",
	},
	question: "Where is the warranty?",
	messages: [],
	book: {
		id: "fixed-book",
		title: "Fixture",
		page: 1,
		text: "Introduction",
		notes: "",
		selection: "",
		providedCharacters: 12,
		scope: { mode: "book", startPage: 1, endPage: 6 },
	},
};
const reading = {
	bookID: "fixed-book",
	scope: base.book!.scope,
	readPages: [1, 5],
	sourcePages: [1, 5],
	emptyPages: [],
};

test("Only the selected book and explicit local MCP server enter executor configuration", () => {
	const server = bookServer(base)!;
	expect(server.args).toEqual([
		"reading-mcp",
		"fixed-book",
		"book",
		"1",
		"6",
		"1",
		"12",
	]);
	expect(server.env).toEqual({ BOOKSIDE_DATA_DIR: "/library" });
	const args = claudeArguments("learning", undefined, base);
	expect(args).not.toContain("--safe-mode");
	expect(args).not.toContain("--bare");
	expect(args).toContain("--restricted");
	expect(args).toContain("--strict-mcp-config");
	expect(args[args.indexOf("--setting-sources") + 1]).toBe("");
	expect(JSON.parse(args[args.indexOf("--settings") + 1])).toEqual({
		disableAllHooks: true,
	});
	expect(args[args.indexOf("--tools") + 1]).toBe("");
	for (const tool of claudeBookTools) expect(args).toContain(tool);
	expect(codexArguments(base)).toContain(
		`mcp_servers.bookside.enabled_tools=${JSON.stringify(bookToolNames)}`,
	);
	expect(systemInstructions("auto", "claude", true)).toContain(
		"nextPage/nextOffset",
	);
	expect(systemInstructions("auto", "claude", true)).not.toMatch(/[가-힣]/);
	expect(() =>
		validateRequest({
			...base,
			book: {
				...base.book,
				scope: { mode: "range", startPage: 5, endPage: 2 },
			},
		}),
	).toThrow();
});

test("Only matching tool-result coverage may become clickable evidence", () => {
	const events: Record<string, unknown>[] = [];
	const emit = (e: Record<string, unknown>) => events.push(e);
	for (const invalid of [
		{ ...reading, bookID: "another-book" },
		{ ...reading, sourcePages: [99] },
		{ ...reading, readPages: [0] },
		{ ...reading, scope: { mode: "range", startPage: 1, endPage: 6 } },
	])
		emitBookReading(
			[{ type: "text", text: JSON.stringify({ reading: invalid }) }],
			base,
			emit,
		);
	expect(events).toHaveLength(0);
	emitBookReading(
		[{ type: "text", text: JSON.stringify({ reading }) }],
		base,
		emit,
	);
	expect(events).toEqual([{ type: "reading", reading }]);
});

test("The context meter uses the final response after multiple tool rounds", () => {
	const usage = claudeUsage(
		{
			usage: { input_tokens: 50000, output_tokens: 9000 },
			modelUsage: { chosen: { contextWindow: 200000 } },
		},
		{
			model: "chosen",
			usage: {
				input_tokens: 4000,
				cache_read_input_tokens: 1000,
				output_tokens: 300,
			},
		},
	);
	expect(usage).toMatchObject({
		inputTokens: 5000,
		outputTokens: 300,
		contextWindow: 200000,
	});
});

for (const backend of ["claude", "codex"] as const) {
	test(`${backend} streams book progress and sources through Pi`, async () => {
		const root = await mkdtemp(join(tmpdir(), "bookside-reading-"));
		try {
			const cli = join(root, "runtime-fixture"),
				content = [
					{
						type: "text",
						text: JSON.stringify({
							reading,
							pages: [{ page: 5, text: "Warranty lasts nine years." }],
						}),
					},
				];
			const program =
				backend === "claude"
					? `
if(process.argv.includes('status')){console.log(JSON.stringify({loggedIn:true,authMethod:'claude.ai',apiProvider:'firstParty'}));process.exit(0);}
if(process.env.CLAUDE_CODE_DISABLE_CLAUDE_MDS!=='1'||process.env.CLAUDE_CODE_DISABLE_ATTACHMENTS!=='1')process.exit(2);
process.stdin.resume();process.stdin.on('end',()=>{
const emit=x=>console.log(JSON.stringify(x));
emit({type:'system',subtype:'init',tools:${JSON.stringify(claudeBookTools)},mcp_servers:[{name:'bookside',status:'connected'}],skills:[]});
emit({type:'assistant',message:{content:[{type:'tool_use',id:'read',name:'mcp__bookside__read_pages',input:{start_page:5,end_page:5}}]}});
emit({type:'user',message:{content:[{type:'tool_result',tool_use_id:'read',content:${JSON.stringify(content)}}]}});
emit({type:'stream_event',event:{type:'message_start',message:{id:'final',model:'chosen',usage:{input_tokens:4000,output_tokens:1}}}});
emit({type:'stream_event',event:{type:'message_delta',usage:{output_tokens:80}}});
emit({type:'assistant',message:{id:'final',model:'chosen',usage:{input_tokens:4000,output_tokens:1},content:[]}});
emit({type:'result',subtype:'success',result:'Warranty lasts nine years. [p. 5]',usage:{input_tokens:50000,output_tokens:9000},modelUsage:{chosen:{contextWindow:200000}}});
});`
					: `
const readline=require('node:readline'),send=x=>console.log(JSON.stringify(x));
readline.createInterface({input:process.stdin}).on('line',line=>{const r=JSON.parse(line);if(r.id===undefined)return;const reply=result=>send({id:r.id,result});
switch(r.method){
case 'initialize':reply({});break;
case 'account/read':reply({account:{type:'chatgpt',planType:'test'}});break;
case 'model/list':reply({data:[{id:'fixture',model:'fixture',isDefault:true}]});break;
case 'thread/start':reply({thread:{id:'thread'}});break;
case 'turn/start':
reply({turn:{id:'turn'}});
send({method:'item/started',params:{threadId:'thread',item:{type:'mcpToolCall',id:'read',server:'bookside',tool:'read_pages',arguments:{start_page:5}}}});
send({method:'item/completed',params:{threadId:'thread',item:{type:'mcpToolCall',id:'read',server:'bookside',tool:'read_pages',status:'completed',result:{content:${JSON.stringify(content)}}}}});
send({method:'item/agentMessage/delta',params:{threadId:'thread',delta:'Warranty lasts nine years. [p. 5]'}});
send({method:'turn/completed',params:{threadId:'thread',turn:{status:'completed'}}});break;
default:reply({});}});`;
			await writeFile(cli, "#!/usr/bin/env node\n" + program);
			await chmod(cli, 0o700);
			const events: Record<string, unknown>[] = [];
			await handle(
				{
					...base,
					backend,
					workspace: root,
					codexHome: join(root, "Codex"),
					claudePath: cli,
					codexPath: cli,
				},
				new AbortController().signal,
				(e) => events.push(e),
			);
			expect(
				events.some(
					(e) => e.type === "activity" && String(e.message).includes("5쪽"),
				),
			).toBe(true);
			expect(events.find((e) => e.type === "reading")?.reading).toEqual(
				reading,
			);
			expect(events.find((e) => e.type === "answer")?.text).toContain("[p. 5]");
			if (backend === "claude")
				expect(events.find((e) => e.type === "usage")?.usage).toMatchObject({
					inputTokens: 4000,
					outputTokens: 80,
				});
		} finally {
			await rm(root, { recursive: true, force: true });
		}
	});
}
