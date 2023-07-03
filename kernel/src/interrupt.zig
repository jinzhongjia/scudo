const gate_desc = packed struct {
    offset_low: u16,
    selector: u16,
    IST: u3,
    reserved: u5 = 0,
    flag: flag,
    offset_middle: u16,
    offset_high: u32,
    reserved: u32,
};

const flag = packed struct {
    gate_type: u4,
    reserved: u1 = 0,
    DPL: u2,
    P: u1,
};
