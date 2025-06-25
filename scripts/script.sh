#!/bin/bash

# Usage: ./autocoder.sh <GITHUB_TOKEN> <REPO> <ISSUE_NUMBER> <OPENAI_API_KEY>

GITHUB_TOKEN="$1"
REPOSITORY="$2"
ISSUE_NUMBER="$3"
OPENAI_API_KEY="$4"

# Function to fetch issue details from GitHub
fetch_issue_details() {
    curl -s -H "Authorization: token $GITHUB_TOKEN" \
         "https://api.github.com/repos/$REPOSITORY/issues/$ISSUE_NUMBER"
}

# Function to call OpenAI API
send_prompt_to_chatgpt() {
    curl -s -X POST "https://api.openai.com/v1/chat/completions" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"gpt-3.5-turbo\", \"messages\": $MESSAGES_JSON, \"max_tokens\": 1000}"
}

# Function to save code snippet to file
save_to_file() {
    local filename="autocoder-bot/$1"
    local code_snippet="$2"

    mkdir -p "$(dirname "$filename")"
    echo -e "$code_snippet" > "$filename"
    echo "✅ Saved: $filename"
}

# Start
echo "🔍 Fetching GitHub issue #$ISSUE_NUMBER..."
RESPONSE=$(fetch_issue_details)
ISSUE_BODY=$(echo "$RESPONSE" | jq -r .body)

if [[ -z "$ISSUE_BODY" || "$ISSUE_BODY" == "null" ]]; then
    echo "❌ Issue body is empty or not found."
    exit 1
fi

# Construct prompt
INSTRUCTIONS="Generate a JSON object where keys are file paths and values are code snippets. Output strictly valid JSON — no Markdown or formatting."

FULL_PROMPT="$INSTRUCTIONS\n\n$ISSUE_BODY"
MESSAGES_JSON=$(jq -n --arg content "$FULL_PROMPT" '[{"role":"user","content":$content}]')

# Query OpenAI
echo "💬 Sending prompt to OpenAI..."
RESPONSE=$(send_prompt_to_chatgpt)

if [[ -z "$RESPONSE" ]]; then
    echo "❌ No response from OpenAI API."
    exit 1
fi

# Extract raw message
RAW_CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')

# Remove triple backtick markdown if present
CLEAN_CONTENT=$(echo "$RAW_CONTENT" | sed '/^```/,/^```/d')

# Parse JSON
echo "🧪 Parsing JSON response..."
FILES_JSON=$(echo "$CLEAN_CONTENT" | jq -e '.' 2>/dev/null)
if [[ $? -ne 0 || -z "$FILES_JSON" ]]; then
    echo "❌ Failed to parse JSON. Here is the raw content:"
    echo "$RAW_CONTENT"
    exit 1
fi

# Save each file
echo "📁 Writing files..."
for key in $(echo "$FILES_JSON" | jq -r 'keys[]'); do
    FILENAME="$key"
    CODE_SNIPPET=$(echo "$FILES_JSON" | jq -r --arg key "$key" '.[$key]')
    CODE_SNIPPET=$(echo "$CODE_SNIPPET" | sed 's/\r$//')
    save_to_file "$FILENAME" "$CODE_SNIPPET"
done

echo "✅ All files written successfully."
