import raw from "./agents-data.json";

export type Agent = {
  name: string;
  description: string;
  category: string;
  file: string;
  type: string;
  color: string;
  tools: string[];
  keywords: string[];
  specialization: string;
  complexity: string;
  schema: "standard" | "claude-flow" | "minimal";
  bodyChars: number;
};

export const AGENTS = raw as Agent[];
