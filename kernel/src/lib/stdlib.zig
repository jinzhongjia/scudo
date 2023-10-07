pub fn bcd_to_integer(bcd_value: u8) u8 {
    return (bcd_value & 0xf) + (bcd_value >> 4) * 10;
}

pub fn integer_to_bcd(value: u8) u8 {
    return (value / 10) * 0x10 + (value % 10);
}
