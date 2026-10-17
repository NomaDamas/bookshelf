import DOMPurify from "dompurify";
import mermaid from "mermaid";

declare global {
	interface Window {
		renderArtifact: (
			kind: string,
			source: string,
			dark: boolean,
		) => Promise<void>;
		webkit?: {
			messageHandlers?: {
				artifact?: { postMessage: (value: unknown) => void };
			};
		};
	}
}

const root = document.getElementById("preview")!;
const report = (state: string, error?: string) =>
	window.webkit?.messageHandlers?.artifact?.postMessage({
		state,
		error,
		height: Math.min(480, Math.max(180, root.scrollHeight + 24)),
	});
let revision = 0;

window.renderArtifact = async (kind, source, dark) => {
	const current = ++revision;
	document.documentElement.dataset.theme = dark ? "dark" : "light";
	root.replaceChildren();
	try {
		if (kind === "mermaid") {
			mermaid.initialize({
				startOnLoad: false,
				securityLevel: "strict",
				theme: dark ? "dark" : "default",
				fontFamily: "-apple-system, sans-serif",
				suppressErrorRendering: true,
			});
			const { svg } = await mermaid.render(`diagram${current}`, source);
			if (current !== revision) return;
			root.innerHTML = svg;
		} else if (kind === "svg") {
			root.innerHTML = DOMPurify.sanitize(source, {
				USE_PROFILES: { svg: true, svgFilters: true },
				FORBID_TAGS: ["foreignObject", "script", "a"],
				FORBID_ATTR: ["href", "xlink:href"],
			});
			if (!root.querySelector("svg")) throw new Error("No SVG element found");
		} else if (kind === "html") {
			const frame = document.createElement("iframe");
			frame.setAttribute("sandbox", "allow-scripts");
			frame.setAttribute("title", "Interactive visual");
			frame.setAttribute("referrerpolicy", "no-referrer");
			// The opaque sandbox has no native bridge, storage, file access, or network.
			const policy =
				"default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src data: blob:; media-src data: blob:; font-src data:; connect-src 'none'; frame-src 'none'; object-src 'none'; form-action 'none'; base-uri 'none'";
			frame.srcdoc = `<!doctype html><meta http-equiv="Content-Security-Policy" content="${policy}"><style>:root{color-scheme:${dark ? "dark" : "light"}}body{font:14px -apple-system,sans-serif;margin:16px}svg,img{max-width:100%}*{box-sizing:border-box}</style>${source}`;
			root.append(frame);
		} else throw new Error("Unsupported visual format");
		requestAnimationFrame(() => report("ready"));
	} catch (error) {
		if (current !== revision) return;
		root.replaceChildren();
		report(
			"error",
			String(error instanceof Error ? error.message : error).slice(0, 240),
		);
	}
};
new ResizeObserver(() => report("size")).observe(root);
