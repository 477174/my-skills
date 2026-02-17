---
name: semantic-prompt-craft
description: Methodology for designing LLM system prompts that maximize behavioral effectiveness without creating bias. Use when crafting or refining prompts for any LLM (especially small models like gpt-4.1-nano/mini) where the goal is reliable, unbiased behavior. Covers identity framing, negative boundaries, anti-bias patterns, and small-model optimization. Trigger phrases include 'design a prompt', 'write system instructions', 'fix prompt bias', 'improve extraction prompt', 'nano prompt', 'small model instructions'.
---

# Semantic Prompt Craft

Methodology for designing LLM prompts that are effective, unbiased, and robust across diverse inputs.

## Core Principle

A well-designed prompt unlocks the model's existing capabilities rather than constraining them. The model already knows how to reason — your job is to frame the task correctly and set boundaries, not to micromanage the reasoning process.

## Anti-Bias Rules (NEVER violate)

### 1. No Literal Examples

Examples create cognitive anchors. The model mimics the pattern of the example rather than understanding the underlying behavior. This causes:
- Overfitting to the example's specific domain/wording
- Missing cases that don't resemble the example
- Reduced adaptability to novel inputs

**Instead**: Describe the behavior abstractly. If the model needs to infer implicit information, describe what "implicit inference" means conceptually — don't show it a case of implicit inference.

### 2. No Exhaustive Category Taxonomies

Enumerating categories (e.g., "Category 1: Possession, Category 2: Action, Category 3: Identity...") creates a closed-world assumption. The model will ONLY look for the listed categories and miss anything outside them.

**Instead**: Describe the general principle. "Consider all linguistic and logical implications" is better than listing 6 types of implications.

### 3. No Domain-Specific Rules in Generic Prompts

Rules like "if user mentions pharmacy, set X=true" only work for that specific domain and break for everything else.

**Instead**: Describe the reasoning pattern generically. "When the user's statement logically implies a condition described by a parameter, extract that parameter" works for any domain.

## Prompt Architecture (3 Layers)

### Layer 1 — Identity Framing
Define WHAT the model is, not what it should do. Identity activates capabilities more reliably than instructions.

- "You are an inference engine" > "You should infer things"
- "You are a code reviewer" > "Please review this code"
- Choose identities that imply the desired capabilities

### Layer 2 — Behavioral Principle
One or two sentences describing the core behavioral expectation at the highest level of abstraction. This is the "spirit of the law" that guides edge cases.

- Describe the completeness of the task ("recover the full picture")
- Describe what kind of information matters ("what was said AND what was left implicit")
- Keep it conceptual, not procedural

### Layer 3 — Boundaries (Negative Rules)
Define the edges of acceptable behavior using "always/never" identity statements rather than "DO NOT" prohibitions.

**Why identity framing for negatives**: "You never invent values" processes better than "DO NOT invent values" — especially in small models. Negation ("NOT", "DON'T") activates the prohibited concept and applies negation weakly. Identity statements ("You never...") define behavior as inherent.

- "You always X when Y" (positive boundary)
- "You never X when Y" (negative boundary)
- Keep boundaries minimal — only the critical failure modes

## Small Model Optimization (nano/mini class)

### Conciseness Wins
Research (Alkiek et al., 2025) shows concise instructions outperform verbose ones in small models. Every unnecessary word dilutes the signal.

- Target: 100-150 words for system prompts
- Remove any sentence that doesn't change behavior
- If a section can be cut without losing a behavioral edge case, cut it

### Literal Instruction Following
GPT-4.1 family (including nano) follows instructions more literally than predecessors. This means:
- Vague instructions produce vague behavior
- But over-specified instructions create rigid behavior
- Sweet spot: precise about WHAT, general about HOW

### Forced Tool Calling
When using tool-based extraction with small models:
- Use `tool_choice={"type": "function", "function": {"name": "tool_name"}}` instead of `"auto"`
- `"auto"` lets the model decide not to call the tool, which small models do more often
- Forced calling eliminates the "should I call?" decision and focuses the model on "what arguments?"

### System + User Message Separation
- System message: behavioral identity and boundaries (stable across calls)
- User message: the specific task/input (changes per call)
- Small models benefit more from this separation than large models

## Recall vs Precision Bias

When designing extraction/classification prompts, explicitly state the bias:
- "When in doubt, extract" (recall-biased)
- "When in doubt, skip" (precision-biased)
- Without explicit bias, small models default to precision (miss things)

If a downstream validation step exists, always bias toward recall — let the validator filter false positives.

## Prompt Template (Reference Pattern)

```
[Identity statement — what the model IS]

[Behavioral principle — the core expectation at highest abstraction]

[Task instruction — what to do with the input, referencing tool/schema if applicable]

## Boundaries:

[Positive boundary — "You always X when Y"]

[Negative boundary — "You never X when Y"]

[Bias statement — "When in doubt, do X"]
```

This template produces prompts of ~100-150 words that are effective across model sizes and domains.

## Validation Checklist

Before finalizing any prompt, verify:

- [ ] Zero literal examples (no "Example 1:", no "Input: X -> Output: Y")
- [ ] Zero category enumerations (no "Type 1: ..., Type 2: ..., Type 3: ...")
- [ ] Zero domain-specific rules (works with any input domain)
- [ ] Identity framing present (model IS something, not just DOES something)
- [ ] Boundaries use "always/never" not "DO/DON'T"
- [ ] Under 150 words for small models, under 300 for large
- [ ] Explicit recall/precision bias stated
- [ ] System/user message separation clear
- [ ] Tool choice forced if using tool calling
