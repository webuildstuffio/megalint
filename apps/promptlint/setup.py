"""Setup configuration for PromptLint"""

from setuptools import setup, find_packages

with open("README.md", "r", encoding="utf-8") as fh:
    long_description = fh.read()

setup(
    name="promptlint",
    version="0.1.0",
    description="A developer tool for analyzing, scoring, and optimizing LLM prompts with built-in security scanning and cost estimation",
    long_description=long_description,
    long_description_content_type="text/markdown",
    author="PromptLint Contributors",
    author_email="developer@promptlint.dev",
    url="https://github.com/fyunusa/promptlint",
    project_urls={
        "Bug Tracker": "https://github.com/fyunusa/promptlint/issues",
        "Documentation": "https://github.com/fyunusa/promptlint#readme",
    },
    license="MIT",
    packages=find_packages(),
    python_requires=">=3.11",
    install_requires=[
        "typer>=0.9.0",
        "rich>=13.7.0",
        "pydantic>=2.5.0",
        "pyyaml>=6.0",
        "tiktoken>=0.5.0",
    ],
    extras_require={
        "dev": [
            "pytest>=7.4.0",
            "pytest-cov>=4.1.0",
            "black>=23.12.0",
            "ruff>=0.1.0",
            "mypy>=1.7.0",
            "build>=1.0.0",
            "twine>=4.0.0",
        ],
    },
    entry_points={
        "console_scripts": [
            "promptlint=promptlint.cli:app",
        ],
    },
    classifiers=[
        "Development Status :: 4 - Beta",
        "Environment :: Console",
        "Intended Audience :: Developers",
        "License :: OSI Approved :: MIT License",
        "Natural Language :: English",
        "Operating System :: OS Independent",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.11",
        "Programming Language :: Python :: 3.12",
        "Topic :: Software Development :: Libraries :: Python Modules",
        "Topic :: Text Processing :: Linguistic",
    ],
    keywords="prompt linting analysis optimization security cost estimation",
)
