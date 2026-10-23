hl.monitor({
    output = "DP-1",
    mode = "2560x1440@239.97Hz",
    position = "1920x0",
    scale = 1,
    bitdepth = 10,
    vrr = 1,
    sdrbrightness = 1.2,
    sdrsaturation = 1.0,

    sdr_min_luminance = 0.2,
    sdr_max_luminance = 400,
    min_luminance     = 0,
    max_luminance     = 600,
    max_avg_luminance = 350,
    
})

hl.config({
  cursor = { no_hardware_cursors = 1},
  render = { cm_sdr_eotf = 1, cm_auto_hdr = 1 },
})

hl.monitor({
    output = "HDMI-A-1",
    mode = "1920x1080@164.83Hz",
    position = "0x360",
    scale = 1,
    bitdepth = 10,
})
