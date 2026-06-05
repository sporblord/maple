import { defineConfig } from "vitepress";

// https://vitepress.dev/reference/site-config
export default defineConfig({
	title: "Maple",
	description: "Sparse-set ECS for Luau",
	base: "/maple/",
	themeConfig: {
		// https://vitepress.dev/reference/default-theme-config
		nav: [
			{ text: "Home", link: "/" },
			{ text: "Tutorials", link: "/tutorials" },
			{ text: "API", link: "/api" },
		],

		sidebar: [
			{
				text: "Examples",
				items: [
					//{ text: "Markdown Examples", link: "/markdown-examples" },
				],
			},
		],

		socialLinks: [
			{ icon: "github", link: "https://github.com/vuejs/vitepress" },
		],
	},
});
