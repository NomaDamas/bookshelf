export type ContextUsage = {
	model?: string;
	inputTokens: number;
	outputTokens: number;
	contextWindow?: number;
	cachedInputTokens?: number;
};
const count = (value: unknown) =>
	typeof value === "number" && Number.isFinite(value) && value >= 0
		? Math.floor(value)
		: 0;

export function claudeUsage(
	record: any,
	lastMessage?: any,
): ContextUsage | undefined {
	// Use the latest model response, not a sum of all retrieval rounds in the turn.
	const entries = Object.entries(record.modelUsage ?? {}) as [string, any][];
	const preferred =
		entries.find(([name]) => name === lastMessage?.model) ??
		entries.find(
			([, value]) =>
				count(value.inputTokens) +
					count(value.cacheReadInputTokens) +
					count(value.cacheCreationInputTokens) >
				0,
		);
	const usage = lastMessage?.usage ?? record.usage;
	if (!usage && !preferred) return undefined;
	const data = preferred?.[1];
	return {
		model: lastMessage?.model ?? preferred?.[0],
		inputTokens: usage
			? count(usage.input_tokens) +
				count(usage.cache_read_input_tokens) +
				count(usage.cache_creation_input_tokens)
			: count(data.inputTokens) +
				count(data.cacheReadInputTokens) +
				count(data.cacheCreationInputTokens),
		outputTokens: count(
			lastMessage?.usage?.output_tokens ??
				record.usage?.output_tokens ??
				data?.outputTokens ??
				usage?.output_tokens,
		),
		contextWindow: count(data?.contextWindow) || undefined,
		cachedInputTokens: count(
			usage?.cache_read_input_tokens ?? data?.cacheReadInputTokens,
		),
	};
}

export function codexUsage(
	value: any,
	model: string,
): ContextUsage | undefined {
	if (!value?.last) return undefined;
	return {
		model,
		inputTokens: count(value.last.inputTokens),
		outputTokens: count(value.last.outputTokens),
		contextWindow: count(value.modelContextWindow) || undefined,
		cachedInputTokens: count(value.last.cachedInputTokens),
	};
}
