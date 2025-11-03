// Sample Rust file for testing tree-sitter parsing and highlighting

use std::collections::HashMap;

/// Main entry point
fn main() {
    println!("Hello, Rust!");

    let result = calculate(42);
    println!("Result: {}", result);

    let mut map = HashMap::new();
    map.insert("key", "value");
}

/// Calculate something
fn calculate(value: i32) -> i32 {
    value * 2
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_calculate() {
        assert_eq!(calculate(21), 42);
    }
}
