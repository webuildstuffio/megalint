# PyPI Publishing Guide

## Prerequisites

1. **PyPI Account**: Create account at https://pypi.org/account/register/
2. **API Token**: Generate at https://pypi.org/manage/account/

## Steps to Upload

### 1. Update `.pypirc` with Your Token

Replace `YOUR_TOKEN_HERE` in `~/.pypirc` with your PyPI API token:

```bash
nano ~/.pypirc
```

Paste your token (format: `pypi-AgEIcHlwaS5vcmc...`). Save with Ctrl+X, Y, Enter.

### 2. Test Upload to TestPyPI (Optional but Recommended)

Generate test token at https://test.pypi.org/manage/account/

```bash
cd /Users/fyunusa/Documents/promptlint
source venv/bin/activate
twine upload --repository testpypi dist/*
```

Test install:
```bash
pip install --index-url https://test.pypi.org/simple/ --extra-index-url https://pypi.org/simple/ promptlint
```

### 3. Upload to Production PyPI

```bash
cd /Users/fyunusa/Documents/promptlint
source venv/bin/activate
twine upload dist/*
```

### 4. Verify Installation

```bash
pip install promptlint
promptlint models
```

## PyPI Project Page

Once uploaded, your package will be available at:
- **PyPI**: https://pypi.org/project/promptlint/
- **PyPI Stats**: https://pypistats.org/packages/promptlint

## Future Updates

For version bumps:
1. Update `version = "X.Y.Z"` in `pyproject.toml`
2. Rebuild: `python -m build`
3. Upload: `twine upload dist/*`

## Troubleshooting

- **401 Unauthorized**: Token expired or incorrect
- **400 Bad Request**: File already exists (delete old dist/ and rebuild)
- **403 Forbidden**: Not package owner
