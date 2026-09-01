Host Inventory for Proxmox test results
=======================================

Test scripts create persistent timestamped result directories here.

Standalone examples:
  test/results/YYYYMMDD-HHMMSS-run_all_test-PID/
  test/results/YYYYMMDD-HHMMSS-collectors_test-PID/
  test/results/YYYYMMDD-HHMMSS-prepare_host_test-PID/
  test/results/YYYYMMDD-HHMMSS-run_complete_test-PID/

A test/test_all.sh run creates one parent directory and places each focused
test's results below it.

Result directories intentionally remain after the test so command output,
JSON artifacts, summaries, stderr, timing artifacts, generated reports,
and validation reports can be inspected.
They may be deleted manually when no longer needed.
