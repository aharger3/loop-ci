#!/usr/bin/env bash
# notify.sh <type> <title> <body-file> - the ONLY thing in this repo allowed to touch ntfy.
#
# Austin 2026-08-02: "ntfy notifs are a mess, it needs to be simple and accurate. Just start
# and eta, blocked/human task needed with exact steps to get it running again, and done."
# The old rig sent a rollup per row per phase, which is why nothing got read.
#
# THREE types since 2026-08-09, not four. `recommend` is deleted. Austin: "no 4 pieces it will
# be the third - when the project finishes, i want a link with a summary of what was completed,
# and questions/ideas/tasks that came from each sector." So the questions, ideas and human
# tasks each row raised ride INSIDE `done`, tagged with the row that raised them, instead of
# arriving as their own notification minutes later. One run, one closing message.
#
# Enforcement is the case statement: an unknown type exits 2 and fails the step, so a fourth
# notification cannot be added by accident somewhere else in the workflow.
set -euo pipefail

TYPE="${1:?type: start|blocked|done}"
TITLE="${2:?title}"
BODY="${3:?path to body file}"
TOPIC="${NTFY_TOPIC:-aharg-loop}"

case "$TYPE" in
  start)     PRIO=default; TAGS="rocket"        ;;
  blocked)   PRIO=high;    TAGS="warning"       ;;  # the only one that should wake anyone
  done)      PRIO=default; TAGS="white_check_mark" ;;
  *) echo "notify.sh: refusing unknown type '$TYPE' (start|blocked|done)" >&2; exit 2 ;;
esac

# --data-binary @file, never -d "$string": a body with a newline or a quote in it silently
# truncates otherwise, and a truncated BLOCKED message is a missing resume step.
#
# EXTRA_ACTIONS (optional): one more "view, Label, url" action, joined onto the same header
# with ';' per ntfy's own syntax. Still exactly one Actions header, still only 4 types above -
# this rides on the existing button row, it does not add a new notification.
ACTIONS="view, Open run, ${RUN_URL:-https://github.com}"
[ -n "${EXTRA_ACTIONS:-}" ] && ACTIONS="${ACTIONS}; ${EXTRA_ACTIONS}"

# --retry: ntfy.sh is a free public service and a single 5xx or dropped connection would
# otherwise lose the ONLY signal a run emits. Four types a run, so retrying is free.
curl -sS --fail-with-body --retry 3 --retry-all-errors --retry-delay 2 --max-time 30 \
  -H "Title: ${TITLE}" \
  -H "Priority: ${PRIO}" \
  -H "Tags: ${TAGS}" \
  -H "Actions: ${ACTIONS}" \
  --data-binary "@${BODY}" \
  "https://ntfy.sh/${TOPIC}" > /dev/null
