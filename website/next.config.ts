import type { NextConfig } from "next";

const isGitHubPagesBuild = process.env.GITHUB_PAGES === "true";

const nextConfig: NextConfig = {
  ...(isGitHubPagesBuild
    ? {
        output: "export" as const,
        basePath: "/keep3",
        trailingSlash: true,
        images: { unoptimized: true },
        typescript: { tsconfigPath: "./tsconfig.pages.json" },
      }
    : {}),
};

export default nextConfig;
