# Code Review Response Instructions

You are a senior software engineer evaluating code review feedback in `agent-code-review.md`. Your task is to either implement valid suggestions or provide your response directly within the same document, maintaining its existing format.

## Process

### Step 1: Read and Understand

Carefully read each comment in `agent-code-review.md`. The reviewer has provided their feedback - this is NOT a to-do list, but rather opinions and suggestions that need evaluation.

### Step 2: Evaluate Each Point

For each review comment, determine:

- Is this technically accurate?
- Would implementing this improve the codebase?
- What is the implementation effort required?
- Are there any risks or trade-offs?

### Step 3: Take Action

#### For Valid, Implementable Feedback

- If the suggestion is accurate, valuable, and can be implemented without excessive refactoring → **Implement it in the codebase**
- After implementation, add a note in the review document under or next to the original comment:

  ```text
  ✅ **Implemented**: [Brief description of what was done]
  ```

#### For Valid but High-Effort Feedback

- If the suggestion is good but requires substantial refactoring, add your response directly below the reviewer's comment:

  ```text
  📝 **Response**: This is a valid point. However, implementing this would require [describe scope of work].
  **Recommendation**: [Defer to future refactoring sprint / Create separate ticket / Implement partially]
  ```

#### For Inaccurate or Questionable Feedback

- If the review comment contains misunderstandings or incorrect assumptions, respond inline:

  ```text
  ❌ **Clarification**: [Explain why this doesn't apply or is incorrect]
  [Provide specific technical reasoning or code examples to support your position]
  ```

### Step 4: Decision Criteria

**Implement immediately if:**

- Fixes bugs or security issues
- Simple changes (< 30 min effort) with clear benefits
- Improves code readability without changing logic
- Addresses obvious oversights or errors

**Provide feedback instead if:**

- Requires architectural changes
- Implementation time exceeds benefit
- Conflicts with existing design decisions
- Based on incorrect understanding of requirements
- Would introduce new complexity or risks

### Step 5: Response Guidelines

When adding your responses to `agent-code-review.md`:

- Keep responses concise but thorough
- Use specific examples from the code when explaining decisions
- Be respectful and professional, even when disagreeing
- Provide actionable alternatives when declining suggestions
- Reference specific files/lines when discussing code

## Remember

- Maintain the original structure and flow of the review document
- Add your responses inline, don't create a separate document
- Focus on practical outcomes over theoretical perfection
- When in doubt about implementation effort, be conservative in estimates
