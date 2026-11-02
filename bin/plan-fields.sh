#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
usage: plan-fields.sh <plan-body-file>

Turns a plan body written to ~/.claude/rules/feature-plan.md into the fields
dyb_web's add_plan takes, as one JSON object.
USAGE
  exit 64
}

[ $# -eq 1 ] || usage

jq -R -s '
  def trimmed: sub("^\\s+"; "") | sub("\\s+$"; "");
  def paragraphs: [split("\n\n")[] | trimmed | select(length > 0)];
  def named_pairs: [scan("(?m)^- \\*\\*(.+?)\\*\\* — (.+)$") | {name: .[0], body: .[1]}];
  def diagram: capture("```mermaid\n(?<code>[\\s\\S]*?)\n```").code;
  def prose: gsub("```[\\s\\S]*?```"; "") | paragraphs | map(select(startswith("|") | not));
  def line_after($label): [scan("(?m)^\\s*- (?:\\*\\*)?" + $label + ":(?:\\*\\*)? (.+)$")[0]] | first;
  def decisions:
    split("**Answers that change the design**")[0]
    | [splits("(?m)^[0-9]+\\. ") | select(startswith("**"))]
    | map({question: capture("^\\*\\*(?<q>.+?)\\*\\*").q,
           options: [scan("(?m)^\\s*- Option [a-z]+: (.+)$")[0]],
           recommendation: line_after("Recommendation"),
           choice: line_after("Decided")});
  def part($heading): capture("(?m)^## " + $heading + "\n(?<text>[\\s\\S]*?)(?=\n## |\\z)").text | trimmed;
  def listed: [scan("(?m)^- (?:\\[[ x]\\] )?(.+)$")[0]];
  def unit:
    capture("^Unit (?<number>[0-9]+\\.[0-9]+) — (?<title>.+?)(?: \\([^)]+\\))?\n(?<body>[\\s\\S]*)$") as $unit
    | $unit.body as $body
    | {number: $unit.number,
       stage: ($unit.number | split(".")[0] | tonumber),
       title: $unit.title,
       user_story: ($body | split("\n## ")[0] | trimmed),
       part_of: ($body | part("Part of")),
       how_it_fits: (($body | part("How it fits") | diagram) // ""),
       acceptance_criteria: ($body | part("Acceptance criteria") | listed),
       out_of_scope: ($body | part("Out of scope") | listed),
       waits_on: [$body | part("Dependencies") | scan("Unit ([0-9]+\\.[0-9]+)")[0]]};
  def units: [splits("(?m)^#### ") | select(startswith("Unit ")) | sub("(?m)\n### Stage[\\s\\S]*$"; "") | unit];
  def sections:
    sub("\n---\n## Generation Metadata[\\s\\S]*$"; "")
    | [splits("\n(?=## [0-9]{2} )")]
    | map(capture("^## (?<number>[0-9]{2}) [^\n]*\n(?<body>[\\s\\S]*)$")) | map({(.number): .body}) | add;

  def names: {"01": "The plan", "02": "Already built", "03": "To be added", "04": "How it fits", "05": "How it runs",
               "06": "What we gain", "07": "What we trade", "08": "Settle first", "09": "The work", "10": "Risks"};
  def refuse($why): "plan-fields.sh: \($why)\n" | halt_error(1);

  sections as $sections
  | (first(names | to_entries[] | select($sections[.key] == null)) // null) as $missing
  | if $missing then refuse("the plan has no section \($missing.key) \($missing.value)") else . end
  | ($sections["01"] | paragraphs) as $plan
  | {summary: ($plan | map(select(test("^\\*\\*[^\n]*\\*\\*$") | not)) | join("\n\n")),
     rule: ($plan | map(select(test("^\\*\\*[^\n]*\\*\\*$")) | ltrimstr("**") | rtrimstr("**")) | first),
     already_built: ($sections["02"] | named_pairs),
     to_be_added: ($sections["03"] | named_pairs),
     model_diagram: ($sections["04"] | diagram),
     how_it_fits: ($sections["04"] | prose | map({body: .})),
     flow_diagram: ($sections["05"] | diagram),
     how_it_runs: [$sections["05"] | prose[] | capture("^\\*\\*(?<name>.+?)\\.\\*\\* (?<body>[\\s\\S]+)$")],
     gains: ($sections["06"] | named_pairs | map({role: .name, body})),
     trades: ($sections["07"] | named_pairs),
     decisions: ($sections["08"] | decisions),
     units: ($sections["09"] | units),
     risks: [$sections["10"] | scan("(?m)^- \\*\\*(.+?)\\*\\* (.+)$") | {name: .[0], body: .[1]}]}
' "$1"
