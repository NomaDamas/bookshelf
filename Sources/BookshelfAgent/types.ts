export type Backend = "claude" | "codex";
export type ChatMessage = { role: "user" | "assistant"; text: string };
export type Request = {
	clientVersion?: string;
	action: "status" | "login" | "chat";
	backend: Backend;
	model?: string;
	usePi: boolean;
	skill: "explain" | "compare" | "visualize";
	workspace: string;
	codexHome: string;
	claudePath?: string;
	codexPath?: string;
	question?: string;
	messages?: ChatMessage[];
	book?: {
		id: string;
		title: string;
		page: number;
		text: string;
		notes: string;
		selection: string;
	};
};
export type AccountStatus = {
	connected: boolean;
	billing: "subscription" | "api" | "none";
	label: string;
};
export type Emit = (event: Record<string, unknown>) => void;
