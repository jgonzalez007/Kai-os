# CONTRIBUTING TO KAI OS

## Getting Started

1. Fork the repo
2. Clone: `git clone git@github.com:YOUR_USER/kai-os.git`
3. Open in Xcode, build
4. Create a feature branch: `git checkout -b feature/your-feature`

## Development Process

1. Write tests first (where applicable)
2. Implement the feature
3. Update documentation
4. Submit a PR

## Code Style

- Swift 5.9+ style
- 4-space indentation
- `self.` only when necessary
- Clear, descriptive names
- Comments explain why, not what

## Commit Messages

```
feat: add Kai DoubleTap local model support
fix: handle empty knowledge base in RAG
docs: update architecture diagram
chore: rename project to Kai OS
```

## Testing

Run all tests in Xcode or via command line:
```bash
xcodebuild test -project "Kai OS.xcodeproj" -scheme "Kai OS Tests"
```

## Security

- Never commit API keys
- Use environment variables for secrets
- Report security issues to security@kai-os.ai
- All PII handling must pass security review

## Licensing

Code: MIT
Documentation: CC-BY-4.0
Trademark: Kai OS Labs

---

*Built with care by the Kai OS community.*
