import type { Emit, Request } from "./types.js";

export const bookToolNames = [
	"get_book_overview",
	"search_book",
	"read_pages",
	"get_reading_coverage",
] as const;
export const claudeBookTools = bookToolNames.map(
	(name) => `mcp__bookshelf__${name}`,
);

export function bookServer(request: Request) {
	const scope = request.book?.scope;
	if (!request.reading || !request.book || !scope) return undefined;
	return {
		command: request.reading.command,
		args: [
			"reading-mcp",
			request.book.id,
			scope.mode,
			String(scope.startPage),
			String(scope.endPage),
			String(request.book.page),
			String(request.book.providedCharacters ?? 0),
		],
		env: { BOOKSHELF_DATA_DIR: request.reading.directory },
	};
}

export function isBookTool(
	server: unknown,
	tool: unknown,
	request: Request,
): boolean {
	return (
		Boolean(request.reading) &&
		server === "bookshelf" &&
		typeof tool === "string" &&
		(bookToolNames as readonly string[]).includes(tool)
	);
}

export function bookToolActivity(tool: string, args: any): string {
	if (tool === "search_book") return "책에서 관련 내용을 찾고 있습니다.";
	if (tool === "read_pages" && Number.isInteger(args?.start_page)) {
		const end = args.end_page ?? args.start_page;
		return args.start_page === end
			? `${end}쪽을 읽고 있습니다.`
			: `${args.start_page}~${end}쪽을 읽고 있습니다.`;
	}
	return tool === "get_reading_coverage"
		? "읽은 범위를 확인하고 있습니다."
		: "책의 목차를 확인하고 있습니다.";
}

/** Only parse output belonging to an allowlisted tool call, never assistant prose. */
export function emitBookReading(
	content: unknown,
	request: Request,
	emit: Emit,
) {
	if (!Array.isArray(content)) return;
	for (const block of content) {
		if (block?.type !== "text" || typeof block.text !== "string") continue;
		let value: any;
		try {
			value = JSON.parse(block.text).reading;
		} catch {
			continue;
		}
		const scope = request.book?.scope;
		if (
			!scope ||
			value?.bookID !== request.book?.id ||
			value.scope?.startPage !== scope.startPage ||
			value.scope?.endPage !== scope.endPage ||
			value.scope?.mode !== scope.mode
		)
			continue;
		const valid = (pages: unknown) =>
			Array.isArray(pages) &&
			pages.length <= scope.endPage - scope.startPage + 1 &&
			pages.every(
				(p) =>
					Number.isInteger(p) && p >= scope.startPage && p <= scope.endPage,
			);
		if ([value.readPages, value.sourcePages, value.emptyPages].every(valid))
			emit({ type: "reading", reading: value });
	}
}
