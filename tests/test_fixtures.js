#!/usr/bin/env node
/* Offline fixture contract check; intentionally uses only Node's stdlib. */
const fs = require('fs');
const path = require('path');

const dir = path.join(__dirname, '..', 'fixtures');
const issues = JSON.parse(fs.readFileSync(path.join(dir, 'issues.json'), 'utf8'));
if (!Array.isArray(issues) || issues.length < 2) throw new Error('issues fixture is too small');
const fields = ['id', 'shortId', 'title', 'culprit', 'project', 'environment', 'level',
  'priority', 'hasSeen', 'status', 'substatus', 'isUnhandled', 'isRegression', 'count', 'userCount',
  'firstSeen', 'lastSeen', 'assignedTo', 'permalink'];
for (const issue of issues) {
  for (const field of fields) if (!(field in issue)) throw new Error(`missing issue field ${field}`);
  if (!('inInbox' in issue) && !('inbox' in issue)) throw new Error('missing Sentry inbox state');
  const detail = JSON.parse(fs.readFileSync(path.join(dir, `issue-${issue.id}.json`), 'utf8'));
  if (!Array.isArray(detail.entries) || !detail.entries.length) throw new Error('detail lacks event entries');
  const frames = detail.entries[0]?.data?.values?.[0]?.stacktrace?.frames || [];
  if (!frames.length || !('filename' in frames[0]) || !('inApp' in frames[0])) throw new Error('detail lacks stack frames');
  if (!Array.isArray(detail.breadcrumbs?.values) || !detail.breadcrumbs.values.length) throw new Error('detail lacks breadcrumbs');
}
console.log('test_fixtures.js: ok');
