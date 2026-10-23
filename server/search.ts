export type SearchSource = {
  title: string;
  url: string;
  content: string;
  score?: number;
};

export function shouldSearch(prompt: string): boolean {
  return /\b(latest|today|current|currently|recent|news|right now|this week|this month|as of|source|sources|citation|citations|fact.?check|verify|look up|search the web|web search|who is the current|price today|weather today|breaking|latest version)\b/i.test(prompt) || /(আজ|এখন|বর্তমান|সাম্প্রতিক|খবর|যাচাই|সোর্স|তথ্যসূত্র|আজকের|সর্বশেষ)/i.test(prompt);
}

export async function searchWeb(query: string): Promise<SearchSource[]> {
  const apiKey = process.env.TAVILY_API_KEY;
  if (!apiKey) return [];

  const response = await fetch("https://api.tavily.com/search", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      query: query.slice(0, 400),
      search_depth: "basic",
      topic: "general",
      max_results: 5,
      include_answer: false,
      include_raw_content: false,
    }),
    signal: AbortSignal.timeout(12_000),
  });

  if (!response.ok) {
    console.warn("[search] Tavily request failed", response.status);
    return [];
  }

  const data = (await response.json()) as {
    results?: Array<{ title?: string; url?: string; content?: string; score?: number }>;
  };

  return (data.results || [])
    .filter((item) => typeof item.url === "string" && /^https?:\/\//i.test(item.url))
    .slice(0, 5)
    .map((item) => ({
      title: String(item.title || item.url).slice(0, 240),
      url: String(item.url),
      content: String(item.content || "").slice(0, 2500),
      score: typeof item.score === "number" ? item.score : undefined,
    }));
}
