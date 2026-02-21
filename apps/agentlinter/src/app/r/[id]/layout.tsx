import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "AgentLinter Report",
  description: "Agent workspace lint report — score, tier, and prescriptions.",
  openGraph: {
    title: "AgentLinter Report",
    description: "See how this agent workspace scored.",
    siteName: "AgentLinter",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "AgentLinter Report",
    description: "See how this agent workspace scored.",
  },
};

export default function ReportLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return <>{children}</>;
}
