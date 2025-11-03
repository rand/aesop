# Sample Python file for testing tree-sitter parsing and highlighting

from typing import List, Dict

def main():
    """Main entry point"""
    greeting = "Hello, Python!"
    print(greeting)

    result = calculate(42)
    print(f"Result: {result}")

    data = {"key": "value"}
    process_data(data)

def calculate(value: int) -> int:
    """Calculate something"""
    return value * 2

@decorator
def process_data(data: Dict[str, str]) -> None:
    """Process data with decorator"""
    for key, value in data.items():
        print(f"{key}: {value}")

if __name__ == "__main__":
    main()
