---
name: ig-research
description: "Scrape and analyze Instagram posts by keyword for any project. Use this skill whenever the user wants to search Instagram for content by topic, find trending posts, monitor influencers, analyze engagement on topic-related posts, or build a research dataset from social media. Also trigger when the user says 'scrape Instagram', 'find posts about [topic]', 'social listening for [topic]', or 'what's trending on IG about [topic]'. Use this even for general social media research on any topic."
---

# ig-research

---

## Trigger Phrases

This skill triggers on any of:
- "Instagram research"
- "scrape Instagram"
- "social media research"
- "find Instagram posts"
- "social listening"
- "Instagram content"
- "IG research"
- "what's trending on Instagram about [topic]"
- "find popular posts about [topic]"

---

## Workflow Overview

This skill automates Instagram keyword research for any topic. It:
1. Accepts search keywords from the user (required, no default)
2. Uses Apify's Instagram scraper to retrieve posts
3. Ranks results by engagement (likes + comments)
4. Extracts post metadata and extracts themes
5. Outputs a structured markdown report to the research/ directory

**Time estimate:** 5-15 minutes depending on result volume.

---

## Step-by-Step Process

### Step 1: Accept User Input

Ask for:
- **Primary keyword** (required, e.g., "cold plunge", "home barista", "trail running")
- Optional related keywords (e.g., "cold plunge recovery", "cold plunge routine")
- Engagement threshold (optional; default: top 20 posts)

```
Examples:
- User: "Research cold plunge Instagram posts"
  -> Use keyword: "cold plunge"
- User: "Find posts about home espresso and workflow"
  -> Use keywords: "home espresso workflow"
```

### Step 2: Search for Instagram Scraper on Apify

Use `search-actors` to find Instagram scraping tools:

```
Keywords to search: "Instagram posts" or "Instagram scraper"
Look for: An Actor that can search by keyword and return post data
Expected: Tools like apify/instagram-scraper or similar
```

Once found, note the Actor name (e.g., `apify/instagram-scraper`).

### Step 3: Fetch Actor Details

Use `fetch-actor-details` with the Actor name to review:
- Input schema (what parameters it accepts)
- Output schema (what fields are returned)
- Pricing and rate limits

### Step 4: Run the Instagram Scraper

Use `call-actor` with parameters like:

```
{
  "searchKeyword": "<USER_KEYWORD>",
  "maxResults": 50,
  "onlyVerified": false,
  "includeComments": true
}
```

Adjust parameters based on the Actor's actual input schema.

### Step 5: Process and Filter Results

Use `get-actor-output` to retrieve the full dataset. Then:

1. **Calculate engagement score** for each post:
   ```
   Engagement = likes + comments
   ```

2. **Sort by engagement** (highest first)

3. **Extract key fields:**
   - Post URL
   - Instagram handle (@username)
   - Caption excerpt (first 100 characters)
   - Likes count
   - Comments count
   - Post date (ISO format)
   - Media type (photo, video, carousel)
   - Follower count of account (if available)

4. **Filter out:**
   - Spam or low-quality posts
   - Unrelated hashtag spam
   - Dead/deleted posts

### Step 6: Identify Themes and Patterns

Scan the filtered posts for recurring themes:

- **Key topics:** Identify the dominant subtopics within the search keyword
- **Sentiment:** positive testimonials, educational, controversy/criticism
- **Account types:** brands, influencers, researchers, personal stories, practitioners
- **Content formats:** testimonials, educational videos, before/after, news coverage

### Step 7: Generate Output Report

Create a markdown file in `research/` with this structure:

```markdown
# [Keyword] Instagram Posts (by Engagement)

**Scraped:** [ISO date] | **Source:** Apify Instagram Keyword Search | **Query:** "[keyword]"

---

## Top 10 / 20 Posts

### 1. [likes] likes | @[handle] | [date]
**[Title/headline from caption]**
[Caption excerpt, 100-150 words]
[Comment count] comments.
[Post URL]

### 2. ...

---

## Key Themes

- **Theme 1:** [Description + examples]
- **Theme 2:** [Description + examples]
- **Theme 3:** [Description + examples]

---

## Top Accounts by Reach

| Account | Handle | Followers | Notable Content |
|---------|--------|-----------|-----------------|
| [Name] | @[handle] | [count] | [brief desc] |

---

## Engagement Stats

- **Avg likes per post:** [number]
- **Avg comments per post:** [number]
- **Top post engagement:** [likes + comments]
- **Content types:** [breakdown by photo/video/carousel]

---

## Suggested Keywords for Follow-up

- [Keyword 1]
- [Keyword 2]
- [Keyword 3]
```

**Naming convention:**
- `{keyword}-instagram-{descriptor}.md`
- Examples:
  - `cold-plunge-instagram-top10.md`
  - `home-espresso-instagram-research.md`

### Step 8: Save and Summarize

1. Save the markdown report to `research/` directory
2. Report back to user with:
   - Total posts analyzed
   - Top 3 themes identified
   - Link to the report
   - Suggested next steps (follow-up keywords, accounts to monitor)

---

## Keyword Tips

**Effective search keywords:**
- Start with the broadest term for your topic
- Add modifiers for subtopics (e.g., "[topic] recovery", "[topic] science")
- Combine with audience segments (e.g., "[topic] veterans", "[topic] women")
- Combine with location (e.g., "[topic] Mexico", "[topic] South Africa")

---

## Accounts to Monitor (Template)

Customize this section per project. Add accounts relevant to your topic:

| Account | Focus | Notes |
|---------|-------|-------|
| @example_account | [Topic area] | [Why they matter] |
| @another_account | [Topic area] | [Engagement level, content type] |

Populate this list based on initial research results or prior knowledge of the space.

---

## Apify MCP Tools Available

You have access to these Apify tools via MCP:

1. **search-actors** - Find scrapers by keyword
   - Use to discover the right Instagram scraper Actor

2. **fetch-actor-details** - Get Actor specs
   - Input schema, output schema, pricing, docs

3. **call-actor** - Run the scraper
   - Pass search keyword + parameters, wait for completion

4. **get-actor-output** - Retrieve results
   - Extract the dataset from a completed run

**Example workflow:**
```
search-actors("Instagram posts")
-> fetch-actor-details("apify/instagram-scraper")
-> call-actor("apify/instagram-scraper", {searchKeyword: "<USER_KEYWORD>"})
-> get-actor-output(datasetId)
```

---

## Content Guardrails

Follow the project's CLAUDE.md for any topic-specific content guidelines (medical disclaimers, legal notes, terminology preferences). If the project has no specific guardrails, apply general best practices: flag unverified claims, note legal restrictions where relevant, and avoid presenting social media posts as authoritative sources.

---

## Expected Outputs

**Per run:**
- 1 markdown report in `research/` directory
- File naming: `{keyword}-instagram-{descriptor}.md`
- 300-2000 words (research summary + data table)

**Artifacts:**
- Structured post data (URL, handle, engagement metrics)
- Ranked by engagement
- Theme analysis section
- Top accounts summary

---

## Troubleshooting

**"Actor not found"**
- The Instagram scraper may be under a different name (e.g., `instagram-posts-scraper`)
- Search with broader terms: "Instagram", "social media scraper"
- Check Apify Store directly for the latest Actor name

**"Rate limit hit"**
- Apify has usage limits; respect them
- Wait before running subsequent searches
- Consider batch runs during off-peak hours

**"No results for keyword"**
- Keyword may be too niche (try the broadest term alone or with one modifier)
- Try alternative spellings or related terms
- Check if the keyword has any posts by searching manually first

---

## Iteration & Updates

After running this skill:
1. Review the generated report manually
2. Note any themes that surprised you
3. Suggest follow-up keywords or account deep-dives
4. Store the report in git alongside project notes

This skill is designed to scale. Run it weekly or bi-weekly to track trending content.
