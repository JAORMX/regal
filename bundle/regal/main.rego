package regal.main

import rego.v1

import data.regal.ast
import data.regal.config

lint.notices := notices

lint.aggregates := aggregate

lint_aggregate.violations := aggregate_report

lint.violations := report

# METADATA
# description: Runs all rules against an input AST and produces a report
# entrypoint: true
report contains violation if {
	not is_object(input)

	violation := {
		"category": "error",
		"title": "invalid-input",
		"description": "provided input must be a JSON AST",
	}
}

report contains violation if {
	not input["package"]

	violation := {
		"category": "error",
		"title": "invalid-input",
		"description": "provided input must be a JSON AST",
	}
}

rules_to_run[category][title] if {
	some category, title
	config.merged_config.rules[category][title]

	config.for_rule(category, title).level != "ignore"
	not config.excluded_file(category, title, input.regal.file.name)
}

notices contains notice if {
	some category, title
	some notice in grouped_notices[category][title]
}

grouped_notices[category][title] contains notice if {
	some category, title
	rules_to_run[category][title]

	some notice in data.regal.rules[category][title].notices
}

# Check bundled rules
report contains violation if {
	some category, title
	rules_to_run[category][title]

	count(object.get(grouped_notices, [category, title], [])) == 0

	some violation in data.regal.rules[category][title].report

	not ignored(violation, ignore_directives)
}

# Check custom rules
report contains violation if {
	some category, title

	violation := data.custom.regal.rules[category][title].report[_]

	config.for_rule(category, title).level != "ignore"
	not config.excluded_file(category, title, input.regal.file.name)

	not ignored(violation, ignore_directives)
}

# Collect aggregates in bundled rules
aggregate[category_title] contains entry if {
	some category, title
	rules_to_run[category][title]

	some entry in data.regal.rules[category][title].aggregate

	category_title := concat("/", [category, title])
}

# Collect aggregates in custom rules
aggregate[category_title] contains entry if {
	some category, title

	config.for_rule(category, title).level != "ignore"
	not config.excluded_file(category, title, input.regal.file.name)

	some entry in data.custom.regal.rules[category][title].aggregate

	category_title := concat("/", [category, title])
}

# METADATA
# description: Check bundled rules using aggregated data
# schemas:
#   - input: schema.regal.aggregate
aggregate_report contains violation if {
	some category, title
	rules_to_run[category][title]

	key := concat("/", [category, title])
	input_for_rule := object.remove(
		object.union(input, {"aggregate": object.get(input, ["aggregates_internal", key], [])}),
		["aggregates_internal"],
	)

	some violation in data.regal.rules[category][title].aggregate_report with input as input_for_rule

	not ignored(violation, ignore_directives)
}

# METADATA
# description: Check custom rules using aggregated data
# schemas:
#   - input: schema.regal.aggregate
aggregate_report contains violation if {
	some key in object.keys(input.aggregates_internal)
	[category, title] := split(key, "/")

	config.for_rule(category, title).level != "ignore"
	not config.excluded_file(category, title, input.regal.file.name)

	input_for_rule := object.remove(
		object.union(input, {"aggregate": input.aggregates_internal[key]}),
		["aggregates_internal"],
	)

	some violation in data.custom.regal.rules[category][title].aggregate_report with input as input_for_rule

	not ignored(violation, ignore_directives)
}

ignored(violation, directives) if {
	ignored_rules := directives[violation.location.row]
	violation.title in ignored_rules
}

ignored(violation, directives) if {
	ignored_rules := directives[violation.location.row + 1]
	violation.title in ignored_rules
}

ignore_directives[row] := rules if {
	some comment in ast.comments_decoded
	text := trim_space(comment.Text)

	startswith(text, "regal")

	i := indexof(text, "ignore:")
	i != -1

	list := regex.replace(substring(text, i + 7, -1), `\s`, "")

	row := comment.Location.row + 1
	rules := split(list, ",")
}
