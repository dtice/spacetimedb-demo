pub fn validate_name(name: String) -> Result<String, String> {
    if name.is_empty() {
        Err("Names must not be empty".to_string())
    } else {
        Ok(name)
    }
}

pub fn validate_message(text: String) -> Result<String, String> {
    if text.is_empty() {
        Err("Messages must not be empty".to_string())
    } else {
        Ok(text)
    }
}

pub fn mass_to_cow_size(mass: u32) -> f32 {
    // Convert mass to size in meters
    // Assuming mass is in kg and size is in meters
    // This is a placeholder conversion, adjust as needed
    (mass as f32).sqrt()
}