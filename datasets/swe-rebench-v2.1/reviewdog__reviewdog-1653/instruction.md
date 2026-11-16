[BUG] Sarif format not working
```yml

vulnerability-scanning:
    runs-on: ubuntu-latest
    name: Vulnerability Scanning
    needs: [lint, test]
    timeout-minutes: 5
    permissions:
      id-token: write
      contents: write
      actions: read
      issues: write
      pull-requests: write
    steps:
      - name: Code checkout
        uses: actions/checkout@v3

      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@0.14.0
        with:
          scan-type: 'config'
          scan-ref: ./
          exit-code: '0'
          ignore-unfixed: true
          severity: 'CRITICAL,HIGH'
          format: 'sarif'
          output: 'trivy-config-scan.sarif'

      - uses: actions/upload-artifact@v3
        with:
          name: trivy-config-scan.sarif
          path: trivy-config-scan.sarif

      - uses: reviewdog/action-setup@v1
        with:
          reviewdog_version: v0.15.0

      - name: Run reviewdog
        env:
          REVIEWDOG_GITHUB_API_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          echo -n "$(cat trivy-config-scan.sarif)" | reviewdog -reporter=github-pr-review -f=sarif -level=info -diff="git diff FETCH_HEAD"
```

The command `echo -n "$(cat trivy-config-scan.sarif)" | reviewdog -reporter=github-pr-review -f=sarif -level=info -diff="git diff FETCH_HEAD"`

Doesn't produce anything, or even any log.

### Additional contract requirements

- A SARIF result with a file artifact location must be surfaced as a reviewdog diagnostic even when it has no region or line information.
