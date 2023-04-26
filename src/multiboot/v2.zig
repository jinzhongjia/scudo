const MAGIC: u32 = 0xE85250D6;

const ARCHITECTURE_I386: u32 = 0;

pub const Header = extern struct {
    magic: u32 = MAGIC,
    architecture: u32 = ARCHITECTURE_I386,
    header_length: u32 = @sizeOf(Header),
    checksum: u32 = ~(MAGIC +% ARCHITECTURE_I386 +% @sizeOf(Header)) +% 1,

    ///
    //
    // you can add more tags in here
    //
    ///

    // Here define the end of header
    end_type: u16 = 0,
    end_flags: u16 = 0,
    end_size: u32 = 8,
};


