import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "AgentLinter — Linter for CLAUDE.md & AI Agents",
  description:
    "Optimized for Anthropic's CLAUDE.md. Score, diagnose, and auto-fix your agent workspace files.",
  openGraph: {
    title: "AgentLinter — Linter for CLAUDE.md & AI Agents",
    description: "Optimized for Anthropic's CLAUDE.md. Score, diagnose, and auto-fix your agent workspace files.",
    url: "https://agentlinter.com",
    siteName: "AgentLinter",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "AgentLinter — Linter for CLAUDE.md & AI Agents",
    description: "Optimized for Anthropic's CLAUDE.md. Score, diagnose, and auto-fix your agent workspace files.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <head>
        <meta
          name="viewport"
          content="width=device-width, initial-scale=1, viewport-fit=cover"
        />
        <link
          href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap"
          rel="stylesheet"
        />
        <link
          href="https://api.fontshare.com/v2/css?f[]=clash-display@600,700&display=swap"
          rel="stylesheet"
        />
      </head>
      <body>{children}</body>
    </html>
  );
}
