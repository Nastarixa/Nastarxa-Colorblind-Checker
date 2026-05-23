#Requires AutoHotkey v2.0
#SingleInstance Force
TraySetIcon "Colorblind.ico"

APP_GUI := 0

; ===================================================================
; GDI+ Wrapper
; ===================================================================
class GDI {
    static pToken := 0

    static Startup() {
        if this.pToken
            return
        si := Buffer(24, 0)
        NumPut("UPtr", 1, si, 0)
        NumPut("UPtr", 0, si, 8)
        DllCall("gdiplus\GdiplusStartup", "Ptr*", &pToken:=0, "Ptr", si, "Ptr", 0)
        this.pToken := pToken
    }

    static Shutdown() {
        token := this.pToken
        this.pToken := 0
        if token
            try DllCall("gdiplus\GdiplusShutdown", "Ptr", token)
    }

    static LoadImage(file) {
        pImage := 0
        DllCall("gdiplus\GdipLoadImageFromFile", "WStr", file, "Ptr*", &pImage)
        if !pImage
            return 0
        dpi := this.GetResolution(pImage)
        dims := this.GetDimensions(pImage)
        pBitmap := this.CloneBitmapArea(pImage, 0, 0, dims.w, dims.h)
        if pBitmap
            this.SetResolution(pBitmap, dpi.x, dpi.y)
        this.DisposeImage(pImage)
        return pBitmap
    }

    static CloneImage(pBitmap) {
        dims := this.GetDimensions(pBitmap)
        return this.CloneBitmapArea(pBitmap, 0, 0, dims.w, dims.h)
    }

    static CloneBitmapArea(pBitmap, x, y, w, h) {
        pClone := this.CreateBitmap(w, h)
        if !pClone
            return 0
        if !this.DrawBitmap(pClone, pBitmap, 0, 0, w, h, x, y, w, h) {
            this.DisposeImage(pClone)
            return 0
        }
        return pClone
    }

    static DisposeImage(pBitmap) {
        if pBitmap
            try DllCall("gdiplus\GdipDisposeImage", "Ptr", pBitmap)
    }

    static GetHBITMAP(pBitmap) {
        hBitmap := 0
        DllCall("gdiplus\GdipCreateHBITMAPFromBitmap", "Ptr", pBitmap, "Ptr*", &hBitmap, "UInt", 0xFF000000)
        return hBitmap
    }

    static GetDimensions(pBitmap) {
        DllCall("gdiplus\GdipGetImageDimension", "Ptr", pBitmap, "Float*", &w:=0, "Float*", &h:=0)
        return {w: Integer(w), h: Integer(h)}
    }

    static GetResolution(pBitmap) {
        DllCall("gdiplus\GdipGetImageHorizontalResolution", "Ptr", pBitmap, "Float*", &x:=96.0)
        DllCall("gdiplus\GdipGetImageVerticalResolution", "Ptr", pBitmap, "Float*", &y:=96.0)
        return {x: x, y: y}
    }

    static SetResolution(pBitmap, dpiX, dpiY) {
        if !pBitmap
            return
        if dpiX <= 0
            dpiX := 96
        if dpiY <= 0
            dpiY := 96
        DllCall("gdiplus\GdipBitmapSetResolution", "Ptr", pBitmap, "Float", dpiX, "Float", dpiY)
    }

    static GetPixel(pBitmap, x, y) {
        DllCall("gdiplus\GdipBitmapGetPixel", "Ptr", pBitmap, "Int", x, "Int", y, "UInt*", &argb:=0)
        return argb
    }

    static SetPixel(pBitmap, x, y, argb) {
        DllCall("gdiplus\GdipBitmapSetPixel", "Ptr", pBitmap, "Int", x, "Int", y, "UInt", argb)
    }

    static GetEncoderClsid(mimeType) {
        static clsids := Map(
            "image/bmp",  "{557CF400-1A04-11D3-9A73-0000F81EF32E}",
            "image/jpeg", "{557CF401-1A04-11D3-9A73-0000F81EF32E}",
            "image/gif",  "{557CF402-1A04-11D3-9A73-0000F81EF32E}",
            "image/tiff", "{557CF405-1A04-11D3-9A73-0000F81EF32E}",
            "image/png",  "{557CF406-1A04-11D3-9A73-0000F81EF32E}"
        )
        if !clsids.Has(mimeType)
            return 0
        clsid := Buffer(16, 0)
        if DllCall("ole32\CLSIDFromString", "WStr", clsids[mimeType], "Ptr", clsid)
            return 0
        return clsid
    }

    static SaveBitmap(pBitmap, file, mimeType) {
        clsid := this.GetEncoderClsid(mimeType)
        if !clsid
            return false
        return DllCall("gdiplus\GdipSaveImageToFile", "Ptr", pBitmap, "WStr", file, "Ptr", clsid, "Ptr", 0) = 0
    }

    static LockBits(pBitmap, &bd) {
        DllCall("gdiplus\GdipGetImageDimension", "Ptr", pBitmap, "Float*", &w:=0, "Float*", &h:=0)
        Rect := Buffer(16, 0)
        NumPut("UInt", 0, Rect, 0)
        NumPut("UInt", 0, Rect, 4)
        NumPut("UInt", w, Rect, 8)
        NumPut("UInt", h, Rect, 12)
        bdSize := A_PtrSize = 8 ? 32 : 24
        bd := Buffer(bdSize, 0)
        DllCall("gdiplus\GdipBitmapLockBits", "Ptr", pBitmap, "Ptr", Rect
            , "UInt", 5, "Int", 0x26200A, "Ptr", bd)
        return {Width: NumGet(bd, 0, "UInt")
              , Height: NumGet(bd, 4, "UInt")
              , Stride: NumGet(bd, 8, "Int")
              , Scan0: NumGet(bd, 16, "UPtr")}
    }

    static UnlockBits(pBitmap, &bd) {
        DllCall("gdiplus\GdipBitmapUnlockBits", "Ptr", pBitmap, "Ptr", bd)
    }

    static CreateBitmap(w, h) {
        pBitmap := 0
        DllCall("gdiplus\GdipCreateBitmapFromScan0", "UInt", Max(1, Round(w)), "UInt", Max(1, Round(h))
            , "Int", 0, "Int", 0x26200A, "Ptr", 0, "Ptr*", &pBitmap)
        return pBitmap
    }

    static DrawBitmap(pDest, pSrc, dstX, dstY, dstW, dstH, srcX, srcY, srcW, srcH) {
        gfx := 0
        if DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pDest, "Ptr*", &gfx)
            return false
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gfx, "Int", 7)
        status := DllCall("gdiplus\GdipDrawImageRectRect", "Ptr", gfx, "Ptr", pSrc
            , "Float", dstX, "Float", dstY, "Float", dstW, "Float", dstH
            , "Float", srcX, "Float", srcY, "Float", srcW, "Float", srcH
            , "Int", 2, "Ptr", 0, "Ptr", 0)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gfx)
        return status = 0
    }

    static ApplyColorMatrix(pBitmap, matrix) {
        if !pBitmap
            return 0
        dims := this.GetDimensions(pBitmap)
        pNew := this.CreateBitmap(dims.w, dims.h)
        if !pNew
            return 0

        gfx := 0, attr := 0
        cm := Buffer(100, 0)
        loop 25
            NumPut("Float", matrix[A_Index], cm, (A_Index - 1) * 4)

        if DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pNew, "Ptr*", &gfx) {
            this.DisposeImage(pNew)
            return 0
        }

        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gfx, "Int", 7)
        DllCall("gdiplus\GdipCreateImageAttributes", "Ptr*", &attr)
        DllCall("gdiplus\GdipSetImageAttributesColorMatrix"
            , "Ptr", attr
            , "Int", 1
            , "Int", 1
            , "Ptr", cm
            , "Ptr", 0
            , "Int", 0)

        status := DllCall("gdiplus\GdipDrawImageRectRectI"
            , "Ptr", gfx
            , "Ptr", pBitmap
            , "Int", 0, "Int", 0, "Int", dims.w, "Int", dims.h
            , "Int", 0, "Int", 0, "Int", dims.w, "Int", dims.h
            , "Int", 2
            , "Ptr", attr
            , "Ptr", 0
            , "Ptr", 0)

        DllCall("gdiplus\GdipDisposeImageAttributes", "Ptr", attr)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gfx)

        if status != 0 {
            this.DisposeImage(pNew)
            return 0
        }
        return pNew
    }

    static ResizeBitmap(pBitmap, newW, newH) {
        if !pBitmap
            return 0
        dims := this.GetDimensions(pBitmap)
        if dims.w = newW && dims.h = newH
            return this.CloneImage(pBitmap)
        fit := this.GetFitRect(dims.w, dims.h, newW, newH)
        pNew := this.CreateBitmap(newW, newH)
        if !pNew
            return 0
        gfx := 0
        DllCall("gdiplus\GdipGetImageGraphicsContext", "Ptr", pNew, "Ptr*", &gfx)
        DllCall("gdiplus\GdipGraphicsClear", "Ptr", gfx, "UInt", 0xFF1E2127)
        DllCall("gdiplus\GdipSetInterpolationMode", "Ptr", gfx, "Int", 7)
        DllCall("gdiplus\GdipDrawImageRectRect", "Ptr", gfx, "Ptr", pBitmap
            , "Float", fit.x, "Float", fit.y, "Float", fit.w, "Float", fit.h
            , "Float", 0, "Float", 0, "Float", dims.w, "Float", dims.h
            , "Int", 2, "Ptr", 0, "Ptr", 0)
        DllCall("gdiplus\GdipDeleteGraphics", "Ptr", gfx)
        return pNew
    }

    static GetFitRect(srcW, srcH, maxW, maxH) {
        if srcW <= 0 || srcH <= 0 || maxW <= 0 || maxH <= 0
            return {x: 0, y: 0, w: Max(1, maxW), h: Max(1, maxH)}
        scale := Min(maxW / srcW, maxH / srcH)
        drawW := Max(1, Round(srcW * scale))
        drawH := Max(1, Round(srcH * scale))
        return {
            x: Floor((maxW - drawW) / 2),
            y: Floor((maxH - drawH) / 2),
            w: drawW,
            h: drawH
        }
    }
}

; ===================================================================
; Color Science
; ===================================================================
Linearize(c) {
    if c <= 0.04045
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4
}

Delinearize(c) {
    if c <= 0.0031308
        return c * 12.92
    return 1.055 * (c ** (1 / 2.4)) - 0.055
}

Clamp(v) {
    return Min(Max(v, 0), 255)
}

ApplyMatrix(r, g, b, m) {
    return [
        r * m[1] + g * m[2] + b * m[3],
        r * m[4] + g * m[5] + b * m[6],
        r * m[7] + g * m[8] + b * m[9]
    ]
}

ApplyColorblindMatrixToRgb(r, g, b, m) {
    ; These matrices are tuned to operate directly in sRGB byte space.
    res := ApplyMatrix(r, g, b, m)
    return {
        r: Clamp(Round(res[1])),
        g: Clamp(Round(res[2])),
        b: Clamp(Round(res[3]))
    }
}

; Relative luminance per WCAG 2.1
RelativeLuminance(r, g, b) {
    rl := Linearize(r / 255)
    gl := Linearize(g / 255)
    bl := Linearize(b / 255)
    return 0.2126 * rl + 0.7152 * gl + 0.0722 * bl
}

; WCAG contrast ratio
ContrastRatio(l1, l2) {
    if l1 < l2 {
        tmp := l1, l1 := l2, l2 := tmp
    }
    return (l1 + 0.05) / (l2 + 0.05)
}

; Euclidean distance in linear RGB (perceptual approximation)
ColorDistance(r1, g1, b1, r2, g2, b2) {
    return Sqrt((r1-r2)**2 + (g1-g2)**2 + (b1-b2)**2)
}

; Perceptual color difference (CIE76 simplified in sRGB)
PerceptualDistance(r1, g1, b1, r2, g2, b2) {
    ; Weight green more (human vision is most sensitive to green)
    dr := r1 - r2
    dg := g1 - g2
    db := b1 - b2
    return Sqrt(2 * dr*dr + 4 * dg*dg + 3 * db*db)
}

; ===================================================================
; Colorblind Simulation Matrices (sRGB linear → sRGB linear)
; ===================================================================
GetCBMatrix(type) {
    ; Strong full-dichromacy matrices used by common accessibility tools.
    ; These operate directly in sRGB space and produce a more visible preview.
    static matrices := Map(
        "Deuteranopia", [0.367322, 0.860646, -0.227968,   0.280085, 0.672501, 0.047413,   -0.011820, 0.042940, 0.968881],
        "Protanopia",   [0.152286, 1.052583, -0.204868,   0.114503, 0.786281, 0.099216,   -0.003882, -0.048116, 1.051998],
        "Tritanopia",   [1.255528, -0.076749, -0.178779,   -0.078411, 0.930809, 0.147602,   0.004733, 0.691367, 0.303900]
    )
    if matrices.Has(type)
        return matrices[type]
    return [1, 0, 0,  0, 1, 0,  0, 0, 1]  ; identity
}

GetCBColorMatrix(type) {
    m := GetCBMatrix(type)
    return [
        m[1], m[2], m[3], 0, 0,
        m[4], m[5], m[6], 0, 0,
        m[7], m[8], m[9], 0, 0,
        0,    0,    0,    1, 0,
        0,    0,    0,    0, 1
    ]
}

GetGrayscaleColorMatrix() {
    return [
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0.299, 0.587, 0.114, 0, 0,
        0,     0,     0,     1, 0,
        0,     0,     0,     0, 1
    ]
}

CreateSimulatedBitmap(pBitmap, type, progressCb := 0) {
    pNew := GDI.CloneImage(pBitmap)
    if pNew
        SimulateColorblindness(pNew, type, progressCb)
    return pNew
}

CreateGrayscaleBitmap(pBitmap, progressCb := 0) {
    pNew := GDI.CloneImage(pBitmap)
    if pNew
        ConvertToGrayscale(pNew, progressCb)
    return pNew
}

GetCBDescription(type) {
    static desc := Map(
        "Deuteranopia", "Green-blind (most common, ~6% of males): Difficulty distinguishing green from red.",
        "Protanopia",   "Red-blind (~2% of males): Difficulty distinguishing red from green, reds appear darker.",
        "Tritanopia",   "Blue-blind (rare, <1%): Difficulty distinguishing blue from yellow/green."
    )
    return desc.Has(type) ? desc[type] : ""
}

IsColorblindMode(type) {
    return type = "Deuteranopia" || type = "Protanopia" || type = "Tritanopia"
}

; ===================================================================
; Image Processing
; ===================================================================
SimulateColorblindness(pBitmap, type, progressCb := 0) {
    m := GetCBMatrix(type)
    dims := GDI.GetDimensions(pBitmap)
    loop dims.h {
        y := A_Index - 1
        loop dims.w {
            x := A_Index - 1
            argb := GDI.GetPixel(pBitmap, x, y)
            a := (argb >> 24) & 0xFF
            r := (argb >> 16) & 0xFF
            g := (argb >> 8) & 0xFF
            b := argb & 0xFF
            sim := ApplyColorblindMatrixToRgb(r, g, b, m)
            GDI.SetPixel(pBitmap, x, y, (a << 24) | (sim.r << 16) | (sim.g << 8) | sim.b)
        }
        if progressCb && (Mod(y, 20) = 0 || y = dims.h - 1)
            progressCb.Call(y + 1, dims.h)
    }
}

; Build a "confusion heatmap" showing where colors become indistinguishable
BuildConfusionMap(pOriginal, pSimulated, type) {
    dims := GDI.GetDimensions(pOriginal)
    pHeat := GDI.CloneBitmapArea(pOriginal, 0, 0, dims.w, dims.h)

    origInfo := GDI.LockBits(pOriginal, &bd1)
    simInfo := GDI.LockBits(pSimulated, &bd2)
    heatInfo := GDI.LockBits(pHeat, &bd3)

    origScan := origInfo.Scan0
    simScan := simInfo.Scan0
    heatScan := heatInfo.Scan0
    stride := origInfo.Stride

    maxDist := 0
    distances := []

    loop origInfo.Height {
        y := A_Index - 1
        loop origInfo.Width {
            x := A_Index - 1
            offset := y * stride + x * 4

            ; Original pixel
            ob := NumGet(origScan, offset, "UChar")
            og := NumGet(origScan, offset + 1, "UChar")
            or_ := NumGet(origScan, offset + 2, "UChar")

            ; Simulated pixel
            sb := NumGet(simScan, offset, "UChar")
            sg := NumGet(simScan, offset + 1, "UChar")
            sr := NumGet(simScan, offset + 2, "UChar")

            ; Perceptual distance between original and simulated
            dist := PerceptualDistance(or_, og, ob, sr, sg, sb)
            distances.Push(dist)
            if dist > maxDist
                maxDist := dist
        }
    }

    if maxDist = 0
        maxDist := 1

    ; Second pass: paint heatmap
    idx := 1
    loop origInfo.Height {
        y := A_Index - 1
        loop origInfo.Width {
            x := A_Index - 1
            offset := y * stride + x * 4
            dist := distances[idx]
            idx += 1

            ; Normalize: 0 = no change (green), 1 = big change (red)
            t := dist / maxDist
            ; Invert: small change = BAD (high confusion) = red highlight
            t := 1 - t

            ; Red where colors barely change (confused), green where they change a lot (distinguishable)
            r := Round(255 * t)
            g := Round(255 * (1 - t))
            b := 0

            NumPut("UChar", 0, heatScan, offset)       ; B
            NumPut("UChar", g, heatScan, offset + 1)    ; G
            NumPut("UChar", r, heatScan, offset + 2)    ; R
        }
    }

    GDI.UnlockBits(pOriginal, &bd1)
    GDI.UnlockBits(pSimulated, &bd2)
    GDI.UnlockBits(pHeat, &bd3)

    return pHeat
}

BuildAverageConfusionMap(pOriginal, cbTypes) {
    if cbTypes.Length = 0
        return 0

    heatmaps := []
    locks := []
    pAvg := 0
    avgLocked := false
    try {
        for cbType in cbTypes {
            pSim := CreateSimulatedBitmap(pOriginal, cbType)
            if !pSim
                continue
            pHeat := BuildConfusionMap(pOriginal, pSim, cbType)
            GDI.DisposeImage(pSim)
            if pHeat
                heatmaps.Push(pHeat)
        }

        if heatmaps.Length = 0
            return 0
        if heatmaps.Length = 1
            return heatmaps[1]

        dims := GDI.GetDimensions(heatmaps[1])
        pAvg := GDI.CloneBitmapArea(heatmaps[1], 0, 0, dims.w, dims.h)
        if !pAvg
            return 0

        avgInfo := GDI.LockBits(pAvg, &bdAvg)
        avgLocked := true
        avgScan := avgInfo.Scan0
        stride := avgInfo.Stride

        infos := []
        for pHeat in heatmaps {
            info := GDI.LockBits(pHeat, &bdHeat)
            infos.Push(info)
            locks.Push(bdHeat)
        }

        loop avgInfo.Height {
            y := A_Index - 1
            loop avgInfo.Width {
                x := A_Index - 1
                offset := y * stride + x * 4
                sumB := 0, sumG := 0, sumR := 0
                for info in infos {
                    sumB += NumGet(info.Scan0, offset, "UChar")
                    sumG += NumGet(info.Scan0, offset + 1, "UChar")
                    sumR += NumGet(info.Scan0, offset + 2, "UChar")
                }
                NumPut("UChar", Round(sumB / infos.Length), avgScan, offset)
                NumPut("UChar", Round(sumG / infos.Length), avgScan, offset + 1)
                NumPut("UChar", Round(sumR / infos.Length), avgScan, offset + 2)
            }
        }

        loop heatmaps.Length {
            lock := locks[A_Index]
            GDI.UnlockBits(heatmaps[A_Index], &lock)
        }
        GDI.UnlockBits(pAvg, &bdAvg)
        avgLocked := false

        for pHeat in heatmaps
            GDI.DisposeImage(pHeat)
        return pAvg
    } catch {
        if avgLocked
            try GDI.UnlockBits(pAvg, &bdAvg)
        loop locks.Length {
            lock := locks[A_Index]
            try GDI.UnlockBits(heatmaps[A_Index], &lock)
        }
        for pHeat in heatmaps {
            try GDI.DisposeImage(pHeat)
        }
        if pAvg
            try GDI.DisposeImage(pAvg)
        return 0
    }
}

ConvertToGrayscale(pBitmap, progressCb := 0) {
    dims := GDI.GetDimensions(pBitmap)
    loop dims.h {
        y := A_Index - 1
        loop dims.w {
            x := A_Index - 1
            argb := GDI.GetPixel(pBitmap, x, y)
            a := (argb >> 24) & 0xFF
            r := (argb >> 16) & 0xFF
            g := (argb >> 8) & 0xFF
            b := argb & 0xFF
            gray := Round(0.299 * r + 0.587 * g + 0.114 * b)
            GDI.SetPixel(pBitmap, x, y, (a << 24) | (gray << 16) | (gray << 8) | gray)
        }
        if progressCb && (Mod(y, 20) = 0 || y = dims.h - 1)
            progressCb.Call(y + 1, dims.h)
    }
}

BuildLuminanceMap(pBitmap, progressCb := 0) {
    lums := []
    maxLum := 0
    dims := GDI.GetDimensions(pBitmap)
    loop dims.h {
        y := A_Index - 1
        loop dims.w {
            x := A_Index - 1
            argb := GDI.GetPixel(pBitmap, x, y)
            r := (argb >> 16) & 0xFF
            g := (argb >> 8) & 0xFF
            b := argb & 0xFF
            lum := RelativeLuminance(r, g, b)
            lums.Push(lum)
            if lum > maxLum
                maxLum := lum
        }
        if progressCb && (Mod(y, 20) = 0 || y = dims.h - 1)
            progressCb.Call(y + 1, dims.h * 2)
    }
    if maxLum = 0
        maxLum := 1
    idx := 1
    loop dims.h {
        y := A_Index - 1
        loop dims.w {
            x := A_Index - 1
            argb := GDI.GetPixel(pBitmap, x, y)
            a := (argb >> 24) & 0xFF
            lum := lums[idx]
            idx += 1
            gray := Round(lum / maxLum * 255)
            GDI.SetPixel(pBitmap, x, y, (a << 24) | (gray << 16) | (gray << 8) | gray)
        }
        if progressCb && (Mod(y, 20) = 0 || y = dims.h - 1)
            progressCb.Call(dims.h + y + 1, dims.h * 2)
    }
}

; ===================================================================
; Color Analysis
; ===================================================================
AnalyzeImageColors(pBitmap) {
    dims := GDI.GetDimensions(pBitmap)
    ; Sample pixels (every Nth pixel for performance)
    step := Max(1, Integer(Sqrt(dims.w * dims.h / 5000)))
    colors := Map()
    total := 0

    y := 0
    while y < dims.h {
        x := 0
        while x < dims.w {
            argb := GDI.GetPixel(pBitmap, x, y)
            a := (argb >> 24) & 0xFF
            r := (argb >> 16) & 0xFF
            g := (argb >> 8) & 0xFF
            b := argb & 0xFF

            if a < 24 {
                x += step
                continue
            }

            maxC := Max(r, g, b)
            minC := Min(r, g, b)
            sat := maxC - minC
            lum := RelativeLuminance(r, g, b)

            ; Skip tiny anti-aliased near-black/near-white noise unless saturated.
            if sat < 12 && (lum < 0.015 || lum > 0.97) {
                x += step
                continue
            }

            ; Quantize to reduce noise
            key := (r // 24) * 256 * 256 + (g // 24) * 256 + (b // 24)
            if colors.Has(key)
                colors[key] := colors[key] + 1
            else
                colors[key] := 1
            total += 1
            x += step
        }
        y += step
    }

    if total = 0
        return []

    buckets := []
    for key, count in colors {
        r := (key // (256 * 256)) * 24 + 12
        g := ((key // 256) & 255) * 24 + 12
        b := (key & 255) * 24 + 12
        buckets.Push({r: Min(r, 255), g: Min(g, 255), b: Min(b, 255), count: count})
    }

    ; Sort by count descending.
    loop buckets.Length - 1 {
        i := A_Index
        best := i
        loop buckets.Length - i {
            j := i + A_Index
            if buckets[j].count > buckets[best].count
                best := j
        }
        if best != i {
            temp := buckets[i]
            buckets[i] := buckets[best]
            buckets[best] := temp
        }
    }

    topColors := []
    for bucket in buckets {
        if topColors.Length >= 8
            break

        distinct := true
        for chosen in topColors {
            if PerceptualDistance(bucket.r, bucket.g, bucket.b, chosen.r, chosen.g, chosen.b) < 36 {
                distinct := false
                break
            }
        }

        if distinct {
            topColors.Push({
                r: bucket.r,
                g: bucket.g,
                b: bucket.b,
                pct: Max(1, Round(bucket.count / total * 100))
            })
        }
    }

    ; Fallback: if the image is low-variety, keep the strongest buckets anyway.
    if topColors.Length < 2 {
        topColors := []
        loop Min(8, buckets.Length) {
            bucket := buckets[A_Index]
            topColors.Push({
                r: bucket.r,
                g: bucket.g,
                b: bucket.b,
                pct: Max(1, Round(bucket.count / total * 100))
            })
        }
    }

    return topColors
}

HexColor(r, g, b) {
    return Format("#{:06X}", (r << 16) | (g << 8) | b)
}

SimulateColor(r, g, b, m) {
    return ApplyColorblindMatrixToRgb(r, g, b, m)
}

CalculateColorblindRating(topColors) {
    if topColors.Length < 2
        return {score: 50, grade: "N/A", summary: "Need at least 2 colors to rate."}

    totalPairs := 0
    failingPairs := 0
    weakPairs := 0
    totalCBFail := 0
    totalCBWeak := 0
    cbTypes := ["Deuteranopia", "Protanopia", "Tritanopia"]

    loop topColors.Length - 1 {
        i := A_Index
        c1 := topColors[i]
        loop topColors.Length - i {
            j := i + A_Index
            c2 := topColors[j]
            totalPairs += 1
            l1 := RelativeLuminance(c1.r, c1.g, c1.b)
            l2 := RelativeLuminance(c2.r, c2.g, c2.b)
            cr := ContrastRatio(l1, l2)

            if cr < 3.0
                failingPairs += 1
            else if cr < 4.5
                weakPairs += 1
        }
    }

    for cbType in cbTypes {
        m := GetCBMatrix(cbType)
        loop topColors.Length - 1 {
            i := A_Index
            c1 := topColors[i]
            loop topColors.Length - i {
                j := i + A_Index
                c2 := topColors[j]
                s1 := SimulateColor(c1.r, c1.g, c1.b, m)
                s2 := SimulateColor(c2.r, c2.g, c2.b, m)

                l1 := RelativeLuminance(s1.r, s1.g, s1.b)
                l2 := RelativeLuminance(s2.r, s2.g, s2.b)
                simCR := ContrastRatio(l1, l2)

                pd := PerceptualDistance(s1.r, s1.g, s1.b, s2.r, s2.g, s2.b)
                origPD := PerceptualDistance(c1.r, c1.g, c1.b, c2.r, c2.g, c2.b)

                if origPD > 0 {
                    ratio := pd / origPD
                    if ratio < 0.3
                        totalCBFail += 1
                    else if ratio < 0.6
                        totalCBWeak += 1
                }
            }
        }
    }

    ; Calculate score (0-100)
    contrastScore := 100
    if totalPairs > 0 {
        contrastScore := 100 - (failingPairs / totalPairs * 60) - (weakPairs / totalPairs * 25)
    }
    contrastScore := Max(0, contrastScore)

    cbScore := 100
    totalCBTests := totalPairs * cbTypes.Length
    if totalCBTests > 0 {
        cbScore := 100 - (totalCBFail / totalCBTests * 70) - (totalCBWeak / totalCBTests * 30)
    }
    cbScore := Max(0, cbScore)

    score := Round(contrastScore * 0.4 + cbScore * 0.6)
    grade := "F"
    summary := ""

    if score >= 90 {
        grade := "A"
        summary := "Excellent colorblind accessibility. Your color choices are safe for all common types."
    } else if score >= 75 {
        grade := "B"
        summary := "Good accessibility. Minor issues with some color pairs under certain conditions."
    } else if score >= 55 {
        grade := "C"
        summary := "Fair. Some color pairs may be confused. Consider adjusting contrast or adding redundant cues."
    } else if score >= 35 {
        grade := "D"
        summary := "Poor. Several problematic color combinations detected. Redesign with accessible palette recommended."
    } else {
        grade := "F"
        summary := "Bad. Colors are largely indistinguishable under colorblind simulation. Use a colorblind-friendly palette."
    }

    return {score: score, grade: grade, summary: summary
          , totalPairs: totalPairs, failingPairs: failingPairs, weakPairs: weakPairs
          , totalCBFail: totalCBFail, totalCBWeak: totalCBWeak}
}

GenerateReport(topColors, type) {
    report := ""

    if topColors.Length = 0 {
        report .= "No significant colors detected.`n"
        return report
    }

    ; Rating
    rating := CalculateColorblindRating(topColors)
    report .= "═══════════════════════════════════════`n"
    report .= "  COLORBLIND ACCESSIBILITY RATING: " rating.grade "`n"
    report .= "  Score: " rating.score "/100`n"
    report .= "  " rating.summary "`n"
    report .= "═══════════════════════════════════════`n"
    report .= "`n"

    if rating.totalPairs > 0 {
        report .= "Contrast issues: " rating.failingPairs "/" rating.totalPairs " pairs FAIL, " rating.weakPairs " weak`n"
        report .= "Simulation issues: " rating.totalCBFail " confused, " rating.totalCBWeak " weakened (across all types)`n"
    }
    report .= "`n"

    report .= "Top Colors in Image:`n"
    for c in topColors
        report .= "  " HexColor(c.r, c.g, c.b) " (" c.pct "%)`n"
    report .= "`n"

    ; Check contrast between dominant color pairs
    report .= "Contrast Analysis (WCAG AA = 4.5:1, AAA = 7:1):`n"
    loop topColors.Length - 1 {
        i := A_Index
        c1 := topColors[i]
        loop topColors.Length - i {
            j := i + A_Index
            c2 := topColors[j]
            l1 := RelativeLuminance(c1.r, c1.g, c1.b)
            l2 := RelativeLuminance(c2.r, c2.g, c2.b)
            ratio := ContrastRatio(l1, l2)
            aa := ratio >= 4.5
            aaa := ratio >= 7.0

            report .= "  " HexColor(c1.r, c1.g, c1.b) " vs " HexColor(c2.r, c2.g, c2.b) ": "
            report .= Round(ratio, 1) ":1"
            if aaa
                report .= " (AAA)"
            else if aa
                report .= " (AA)"
            else
                report .= " FAIL"
            report .= "`n"
        }
    }

    report .= "`n"

    ; Check contrast under colorblind simulation
    if type != "" {
        m := GetCBMatrix(type)
        report .= "Under " type " simulation:`n"
        loop topColors.Length - 1 {
            i := A_Index
            c1 := topColors[i]
            loop topColors.Length - i {
                j := i + A_Index
                c2 := topColors[j]

                ; Simulate both colors under colorblindness
                sim1 := SimulateColor(c1.r, c1.g, c1.b, m)
                sim2 := SimulateColor(c2.r, c2.g, c2.b, m)

                ; Perceptual distance under simulation
                pd := PerceptualDistance(sim1.r, sim1.g, sim1.b, sim2.r, sim2.g, sim2.b)
                origDist := PerceptualDistance(c1.r, c1.g, c1.b, c2.r, c2.g, c2.b)

                report .= "  " HexColor(c1.r, c1.g, c1.b) " vs " HexColor(c2.r, c2.g, c2.b) ": "
                if pd < origDist * 0.3
                    report .= "WARNING - colors may look similar!"
                else if pd < origDist * 0.6
                    report .= "CAUTION - reduced distinction"
                else
                    report .= "OK"
                report .= "`n"
            }
        }
    }

    return report
}

; ===================================================================
; Accessibility Suggestions
; ===================================================================
GenerateSuggestions(topColors, type) {
    suggestions := ""

    if topColors.Length < 2 {
        suggestions .= "Not enough distinct colors to analyze.`n"
        return suggestions
    }

    foundIssue := false

    ; Check Red-Green pairs (problematic for deuteranopia/protanopia)
    loop topColors.Length - 1 {
        i := A_Index
        c1 := topColors[i]
        loop topColors.Length - i {
            j := i + A_Index
            c2 := topColors[j]

            ; Pure red/green distinction
            rg1 := c1.r - c1.g
            rg2 := c2.r - c2.g
            diffR := Abs(c1.r - c2.r)
            diffG := Abs(c1.g - c2.g)
            diffB := Abs(c1.b - c2.b)

            ; If colors differ mainly in red and green (not blue), flag for R/G blindness
            if diffR > 30 && diffG > 30 && diffB < 20 {
                foundIssue := true
                suggestions .= "⚠ " HexColor(c1.r, c1.g, c1.b) " vs " HexColor(c2.r, c2.g, c2.b) ": "
                suggestions .= "Relies on red/green difference. Consider adding text labels, icons, or patterns.`n"
            }

            ; Low contrast under simulation
            if type != "" {
                m := GetCBMatrix(type)
                sim1 := SimulateColor(c1.r, c1.g, c1.b, m)
                sim2 := SimulateColor(c2.r, c2.g, c2.b, m)

                l1 := RelativeLuminance(sim1.r, sim1.g, sim1.b)
                l2 := RelativeLuminance(sim2.r, sim2.g, sim2.b)
                cr := ContrastRatio(l1, l2)

                if cr < 3.0 {
                    foundIssue := true
                    suggestions .= "⚠ Under " type " simulation, " HexColor(c1.r, c1.g, c1.b) " vs " HexColor(c2.r, c2.g, c2.b)
                    suggestions .= " has poor contrast (" Round(cr, 1) ":1). "
                    suggestions .= "Suggestion: darken the darker color or lighten the lighter color.`n"
                }
            }
        }
    }

    if !foundIssue
        suggestions .= "✓ No major accessibility issues detected with the current analysis.`n"

    suggestions .= "`nVisual Accessibility Suggestions:`n"
    suggestions .= "  • Add TEXTURE patterns (hatching, dots, stripes) to color areas`n"
    suggestions .= "  • Use SYMBOLS (◼ ● ▲ ◆) or icons alongside color coding`n"
    suggestions .= "  • Add LINE NUMBERS or labels to identify data series`n"
    suggestions .= "  • Use different LINE STYLES (solid, dashed, dotted) for graphs`n"
    suggestions .= "  • Add PATTERNS to charts (crosshatch, stipple, diagonal lines)`n"
    suggestions .= "  • Use marker SHAPES (circle, square, triangle, diamond) for plots`n"
    suggestions .= "`n"
    suggestions .= "Examples of redundant coding:`n"
    suggestions .= "  Charts: dashed blue line + circle markers vs dotted orange line + triangle markers`n"
    suggestions .= "  Maps: crosshatch red area vs dotted blue area`n"
    suggestions .= "  Diagrams: solid green border + checkmark vs dashed red border + cross`n"
    suggestions .= "`nGeneral tips for colorblind accessibility:`n"
    suggestions .= "  • Use text labels or icons in addition to color`n"
    suggestions .= "  • Ensure minimum 4.5:1 contrast ratio (WCAG AA)`n"
    suggestions .= "  • Avoid relying solely on red/green distinctions`n"
    suggestions .= "  • Test your palette with colorblind simulation tools`n"

    ; Palette-based replacement suggestions
    if foundIssue {
        suggestions .= "`nRecommended Colorblind-Safe Alternatives:`n"
        static safePairs := [
            ["Blue", 0x0077BB, "Orange", 0xEE7733],
            ["Blue", 0x0077BB, "Vermillion", 0xCC3311],
            ["Sky Blue", 0x88CCEE, "Orange", 0xDDCC77],
            ["Blue", 0x0077BB, "Green", 0x009988],
            ["Dark Blue", 0x004488, "Orange", 0xEE9944],
            ["Purple", 0xAA44DD, "Yellow", 0xDDCC77]
        ]
        loop safePairs.Length {
            pair := safePairs[A_Index]
            suggestions .= "  " pair[1] " (" HexColor((pair[2]>>16)&0xFF, (pair[2]>>8)&0xFF, pair[2]&0xFF)
                . ") + " pair[3] " (" HexColor((pair[4]>>16)&0xFF, (pair[4]>>8)&0xFF, pair[4]&0xFF) ")`n"
        }
        suggestions .= "`nThese color pairs remain distinguishable under all common types.`n"
    }

    return suggestions
}

; ===================================================================
; Save, Region, Color Picker
; ===================================================================
GetImageMimeFromExt(ext) {
    ext := StrLower(ext)
    if ext = "jpg" || ext = "jpeg"
        return "image/jpeg"
    if ext = "png"
        return "image/png"
    if ext = "bmp"
        return "image/bmp"
    if ext = "gif"
        return "image/gif"
    if ext = "tif" || ext = "tiff"
        return "image/tiff"
    return ""
}

GetDefaultSaveExt(g) {
    if !g.currentFile
        return "png"
    SplitPath(g.currentFile, , , &ext)
    ext := StrLower(ext)
    return GetImageMimeFromExt(ext) ? ext : "png"
}

BuildFilteredBitmapForSave(g, mode, heat := false) {
    if heat && IsColorblindMode(mode) {
        pSim := CreateSimulatedBitmap(g.pOriginal, mode)
        if !pSim
            return 0
        pHeat := BuildConfusionMap(g.pOriginal, pSim, mode)
        GDI.DisposeImage(pSim)
        return pHeat
    }
    if heat && mode = "All Three"
        return BuildAverageConfusionMap(g.pOriginal, ["Deuteranopia", "Protanopia", "Tritanopia"])
    if mode = "Grayscale"
        return CreateGrayscaleBitmap(g.pOriginal)
    if mode = "Luminance" {
        pLum := GDI.CloneImage(g.pOriginal)
        if pLum
            BuildLuminanceMap(pLum)
        return pLum
    }
    if IsColorblindMode(mode)
        return CreateSimulatedBitmap(g.pOriginal, mode)
    return GDI.CloneImage(g.pOriginal)
}

SaveOneFilteredImage(g, pBitmap, path, mime) {
    if !pBitmap
        return false
    dpi := GDI.GetResolution(g.pOriginal)
    GDI.SetResolution(pBitmap, dpi.x, dpi.y)
    return GDI.SaveBitmap(pBitmap, path, mime)
}

SetProgress(g, value, text := "") {
    value := Min(Max(Round(value), 0), 100)
    if HasProp(g, "progress")
        g.progress.Value := value
    if text != "" && HasProp(g, "progressText")
        g.progressText.Value := text
    Sleep -1
}

MarkAnalysisPending(g, reason := "Press Start to apply the selected filter.") {
    g._analysisCurrent := false
    g.statText.Value := reason
    SetProgress(g, 0, "Ready")
}

ClearProcessedImages(g) {
    if g.pSimulated {
        GDI.DisposeImage(g.pSimulated)
        g.pSimulated := 0
    }
    if g.hSimulated {
        DllCall("DeleteObject", "Ptr", g.hSimulated)
        g.hSimulated := 0
    }
    if g.pHeat {
        GDI.DisposeImage(g.pHeat)
        g.pHeat := 0
    }
    if g._sim3Bitmaps {
        for p in g._sim3Bitmaps {
            if p
                GDI.DisposeImage(p)
        }
    }
    g._sim3Bitmaps := []
    g._sim3Scaled := []
}

SaveOutput(g) {
    if !g.pOriginal {
        g.statText.Value := "No image to save."
        return
    }
    if !g._analysisCurrent {
        g.statText.Value := "Press Start before saving the filtered result."
        return
    }
    if g.currentType = "None" {
        g.statText.Value := "Choose a filter mode before saving."
        return
    }
    base := "ColorbindAnalysis"
    if g.currentFile {
        SplitPath(g.currentFile, &name)
        base := SubStr(name, 1, InStr(name, ".", 0, -1) - 1)
    }
    defaultExt := GetDefaultSaveExt(g)
    mime := GetImageMimeFromExt(defaultExt)
    if mime = "" {
        defaultExt := "png"
        mime := "image/png"
    }
    filter := "Same as original (*." defaultExt ")|*." defaultExt "|PNG (*.png)|*.png|JPEG (*.jpg)|*.jpg|BMP (*.bmp)|*.bmp|TIFF (*.tif)|*.tif"
    fn := FileSelect("S16", base "_" StrReplace(StrLower(g.currentType), " ", "_") "." defaultExt, "Save Filtered Image", filter)
    if fn = ""
        return
    SplitPath(fn, , &dir, &ext)
    ext := StrLower(ext)
    mime := GetImageMimeFromExt(ext)
    if mime = "" {
        MsgBox("This output format is not supported by GDI+ save. Use PNG, JPG, BMP, GIF, or TIFF.", "Save Error", "Iconx")
        return
    }

    ; Save report
    try {
        baseName := SubStr(fn, 1, StrLen(fn) - StrLen(ext) - 1)
        txtPath := baseName "_report.txt"
        FileOpen(txtPath, "w", "UTF-8-RAW").Write(g.report.Value)
    }

    ok := true
    SetProgress(g, 5, "Saving filtered image...")
    if g.currentType = "All Three" && !g.chkHeat.Value {
        SplitPath(fn, , , , &nameNoExt)
        basePath := dir "\" nameNoExt
        for mode in ["Deuteranopia", "Protanopia", "Tritanopia"] {
            pOut := BuildFilteredBitmapForSave(g, mode, false)
            outPath := basePath "_" StrLower(mode) "." ext
            ok := SaveOneFilteredImage(g, pOut, outPath, mime) && ok
            if pOut
                GDI.DisposeImage(pOut)
        }
    } else {
        pOut := BuildFilteredBitmapForSave(g, g.currentType, g.chkHeat.Value)
        ok := SaveOneFilteredImage(g, pOut, fn, mime)
        if pOut
            GDI.DisposeImage(pOut)
    }

    SetProgress(g, 100, ok ? "Saved to " dir : "Save failed.")
    if !ok
        MsgBox("Failed to save the filtered image.", "Save Error", "Iconx")
}

ToggleRegionMode(g) {
    g._regionMode := !g._regionMode
    if g._regionMode {
        g._regionPt1 := 0
        g._regionPt2 := 0
        g.btnRegion.Text := "Cancel Region"
        g.statText.Value := "Click top-left corner of region on Original image"
    } else {
        g.btnRegion.Text := "Select Region"
        g.statText.Value := "Region selection cancelled"
    }
}

ClearRegion(g) {
    g._regionMode := false
    g._regionPt1 := 0
    g._regionPt2 := 0
    g._regionX := 0
    g._regionY := 0
    g._regionW := 0
    g._regionH := 0
    g.btnRegion.Text := "Select Region"
    g.regionText.Value := ""
}

ControlPointToImagePoint(ctrl, pBitmap, x, y, &px, &py) {
    if !pBitmap
        return false
    ctrl.GetPos(&cX, &cY, &cw, &ch)
    dims := GDI.GetDimensions(pBitmap)
    scale := Min(cw / dims.w, ch / dims.h)
    imgW := Floor(dims.w * scale)
    imgH := Floor(dims.h * scale)
    offX := Floor((cw - imgW) / 2)
    offY := Floor((ch - imgH) / 2)
    if x < offX || y < offY || x >= offX + imgW || y >= offY + imgH
        return false
    px := Min(dims.w - 1, Max(0, Floor((x - offX) / scale)))
    py := Min(dims.h - 1, Max(0, Floor((y - offY) / scale)))
    return true
}

; Color picker — right-click on original picture
OrigContextMenu(gCtrl, x, y, *) {
    g := gCtrl.Gui
    if !g.pOriginal
        return
    px := 0, py := 0
    if !ControlPointToImagePoint(gCtrl, g.pOriginal, x, y, &px, &py)
        return

    argb := GDI.GetPixel(g.pOriginal, px, py)
    r := (argb >> 16) & 0xFF
    g_ := (argb >> 8) & 0xFF
    b := argb & 0xFF

    info := "Pixel (" px ", " py "):`n"
    info .= "Hex: " HexColor(r, g_, b) "`n"
    info .= "RGB: " r ", " g_ ", " b "`n"
    info .= "Luminance: " Round(RelativeLuminance(r, g_, b), 4) "`n"

    ; Show simulated versions
    for t in ["Deuteranopia", "Protanopia", "Tritanopia"] {
        m := GetCBMatrix(t)
        s := SimulateColor(r, g_, b, m)
        info .= t ": " HexColor(s.r, s.g, s.b) " (RGB " s.r "," s.g "," s.b ")`n"
    }

    g.colorInfo.Value := info
    g.statText.Value := "Color picker at " px "," py
}

; Region selection — left-click on original picture (via OnMessage)
OnOrigClick(wParam, lParam, msg, hwnd, g) {
    if !g._regionMode
        return
    if hwnd = g.origPic.Hwnd {
        x := lParam & 0xFFFF
        y := lParam >> 16
        if x & 0x8000
            x -= 0x10000
        if y & 0x8000
            y -= 0x10000
    } else {
        MouseGetPos(&mx, &my, , &ctrlHwnd, 2)
        if ctrlHwnd != g.origPic.Hwnd
            return
        pt := Buffer(8, 0)
        NumPut("Int", mx, pt, 0)
        NumPut("Int", my, pt, 4)
        DllCall("user32\ScreenToClient", "Ptr", g.origPic.Hwnd, "Ptr", pt)
        x := NumGet(pt, 0, "Int")
        y := NumGet(pt, 4, "Int")
    }
    px := 0, py := 0
    if !ControlPointToImagePoint(g.origPic, g.pOriginal, x, y, &px, &py) {
        g.statText.Value := "Click inside the visible original image."
        return
    }

    if !g._regionPt1 {
        g._regionPt1 := {x: px, y: py}
        g.statText.Value := "Now click bottom-right of region"
        return
    }
    x1 := g._regionPt1.x, y1 := g._regionPt1.y
    x2 := px, y2 := py
    if x1 > x2 {
        t := x1, x1 := x2, x2 := t
    }
    if y1 > y2 {
        t := y1, y1 := y2, y2 := t
    }

    g._regionX := x1
    g._regionY := y1
    g._regionW := x2 - x1 + 1
    g._regionH := y2 - y1 + 1
    g._regionMode := false
    g._regionPt1 := 0
    g.btnRegion.Text := "Select Region"
    g.regionText.Value := Format("Region: {},{} - {}x{}", g._regionX, g._regionY, g._regionW, g._regionH)
    MarkAnalysisPending(g, Format("Region set ({}x{}). Press Start to analyze it.", g._regionW, g._regionH))
}

; ===================================================================
; GUI
; ===================================================================
BuildGui() {
    global APP_GUI
    g := Gui("+Resize +MinSize1050x720", "Nastarxa Image Colorbind Checker")
    g.BackColor := "25282E"
    g.SetFont("s10", "Segoe UI")
    g.MarginX := 14
    g.MarginY := 14

    g.currentFile := ""
    g.currentType := "None"
    g.pOriginal := 0
    g.pSimulated := 0
    g.pHeat := 0
    g.hOriginal := 0
    g.hSimulated := 0
    g.hOrigScaled := 0
    g.hSimScaled := 0
    g._busy := false
    g._sim3Bitmaps := []
    g._sim3Scaled := []
    g._regionMode := false
    g._regionPt1 := 0
    g._regionX := 0
    g._regionY := 0
    g._regionW := 0
    g._regionH := 0
    g._analysisCurrent := false

    ; Top bar
    g.titleText := g.AddText("x14 y12 cFFFFFF", "Image Colorblind Checker")
    g.btnBrowse := g.AddButton("x14 y38 w65 h26", "Browse")
    g.btnBrowse.OnEvent("Click", (*) => BrowseFile(g))
    g.fileText := g.AddText("x89 y42 w300 c909090", "Drop an image here or click Browse")
    g.btnRefresh := g.AddButton("x450 y38 w55 h26", "Start")
    g.btnRefresh.OnEvent("Click", (*) => RefreshAnalysis(g))
    g.btnGuide := g.AddButton("x514 y38 w50 h26", "Guide")
    g.btnGuide.OnEvent("Click", (*) => ShowGuide())
    g.btnSave := g.AddButton("x573 y38 w50 h26", "Save")
    g.btnSave.OnEvent("Click", (*) => SaveOutput(g))
    g.btnRegion := g.AddButton("x632 y38 w80 h26", "Select Region")
    g.btnRegion.OnEvent("Click", (*) => ToggleRegionMode(g))

    ; Simulation type dropdown
    g.lblMode := g.AddText("x722 y42 c909090", "Mode")
    g.cbType := g.AddDropDownList("x780 y38 w135"
        , ["None", "Deuteranopia", "Protanopia", "Tritanopia"
         , "All Three", "Grayscale", "Luminance"])
    g.cbType.OnEvent("Change", (*) => MarkAnalysisPending(g))
    g.cbType.Choose(1)

    ; Image display area
    g.lblOriginal := g.AddText("x14 y76 cFFFFFF", "Original")
    g.origPic := g.AddPicture("x14 y98 w400 h300 Background1E2127")
    g.origPic.OnEvent("ContextMenu", OrigContextMenu)

    g.lblSimulated := g.AddText("x444 y76 cFFFFFF", "Simulation / Heatmap")
    g.simPic := g.AddPicture("x444 y98 w400 h300 Background1E2127")

    ; 3-up simulation labels + pictures (hidden by default)
    g.sim3 := []
    g.lblSim3 := []
    sim3Types := ["Deuteranopia", "Protanopia", "Tritanopia"]
    loop 3 {
        yPos := 98 + (A_Index - 1) * 95
        g.lblSim3.Push(g.AddText("x444 y" yPos " w200 cAAAAAA", sim3Types[A_Index]))
        g.sim3.Push(g.AddPicture("x444 y" (yPos+15) " w400 h76 Background1E2127"))
        g.lblSim3[A_Index].Visible := false
        g.sim3[A_Index].Visible := false
    }

    ; Region & Color info area (between images and report)
    g.regionText := g.AddText("x14 y408 w300 cFFFFFF", "")
    g.chkHeat := g.AddCheckbox("x444 y408 w140 h22 cFFFFFF", "Show confusion map")
    g.chkHeat.OnEvent("Click", (*) => MarkAnalysisPending(g))

    ; Report area
    g.lblAnalysis := g.AddText("x14 y562 cFFFFFF", "Analysis")
    g.progressText := g.AddText("x86 y562 w400 c909090", "Ready")
    g.progress := g.AddProgress("x14 y580 w830 h10 Range0-100", 0)
    g.report := g.AddEdit("x14 y582 w830 h140 ReadOnly BackgroundFFFFFF c000000", "Open an image to begin analysis.")
    g.report.SetFont("s9", "Consolas")

    ; Suggestions area
    g.lblTips := g.AddText("x14 y580 cFFFFFF", "Suggestions")
    g.suggestions := g.AddEdit("x14 y600 w830 h100 ReadOnly BackgroundFFFFFF c000000")

    ; Status
    g.statText := g.AddText("x14 y710 w830 c909090", "Ready")

    ; Events
    g.OnEvent("DropFiles", (gui, files, *) => HandleDrop(g, files))
    g.OnEvent("Size", (gui, minMax, aW, aH) => LayoutGui(g, aW, aH))
    EnableDropFiles(g)

    ; Region selection via left-click on original
    OnMessage(0x201, (w, l, m, h) => OnOrigClick(w, l, m, h, g))
    OnMessage(0x233, (w, l, m, h) => OnDropFiles(w, l, m, h, g))

    g.Show("w1180 h790 Center")
    LayoutGui(g, 1180, 790)
    APP_GUI := g
    return g
}

; ===================================================================
; GUI Events
; ===================================================================
LayoutGui(g, aW, aH) {
    m := 14
    gap := 10
    picGap := 24
    browseRowY := 38
    actionRowY := 74
    titleY := 12
    btnH := 28
    browseW := 82
    refreshW := 70
    guideW := 64
    saveW := 64
    regionW := 98
    modeW := 168
    modeLabelW := 56
    picW := Max(360, Floor((aW - m * 2 - picGap) / 2))
    picH := Min(300, Max(230, aH - 500))
    labelH := 22
    reportH := 96
    suggH := 112

    g.titleText.Move(m, titleY, aW - m * 2, 24)
    g.btnBrowse.Move(m, browseRowY, browseW, btnH)

    modeX := aW - m - modeW
    g.cbType.Move(modeX, browseRowY, modeW, btnH)
    g.lblMode.Move(modeX - modeLabelW - 8, browseRowY + 4, modeLabelW, 22)

    fileX := m + browseW + 12
    fileW := Max(160, modeX - fileX - modeLabelW - 24)
    g.fileText.Move(fileX, browseRowY + 4, fileW, 22)

    refreshX := m
    guideX := refreshX + refreshW + gap
    saveX := guideX + guideW + gap
    regionX := saveX + saveW + gap

    g.btnRefresh.Move(refreshX, actionRowY, refreshW, btnH)
    g.btnGuide.Move(guideX, actionRowY, guideW, btnH)
    g.btnSave.Move(saveX, actionRowY, saveW, btnH)
    g.btnRegion.Move(regionX, actionRowY, regionW, btnH)

    labelY := actionRowY + btnH + 18
    picTop := labelY + 22
    origX := m
    simX := origX + picW + picGap

    g.lblOriginal.Move(origX, labelY, picW, labelH)
    g.lblSimulated.Move(simX, labelY, picW, labelH)
    g.origPic.Move(origX, picTop, picW, picH)
    g.simPic.Move(simX, picTop, picW, picH)

    ; 3-up controls (move to match sim area)
    rowH := (picH - 24) // 3
    rowH := Max(50, rowH)
    loop 3 {
        yPos := picTop + (A_Index - 1) * (rowH + 8)
        g.lblSim3[A_Index].Move(simX, yPos - 2, picW, 16)
        g.sim3[A_Index].Move(simX, yPos + 14, picW, rowH)
    }

    ; Region text row
    chkY := picTop + picH + 12
    g.regionText.Move(origX, chkY, picW, 22)

    ; Fixed lower sections to avoid overlap from dynamic scaling.
    ; Progress is first, then the Analysis/heatmap controls sit below it.
    fullW := simX + picW - m
    progressY := chkY + 28
    progressTextW := 86
    g.progressText.Move(m, progressY - 4, progressTextW, 20)
    g.progress.Move(m + progressTextW + 8, progressY, fullW - progressTextW - 8, 10)

    analysisY := progressY + 22
    g.lblAnalysis.Move(m, analysisY, 70, 20)
    g.chkHeat.Move(simX, analysisY, 220, 22)

    reportY := analysisY + 26
    g.report.Move(m, reportY, fullW, reportH)

    ; Suggestions
    suggY := reportY + reportH + 32
    maxSuggH := Max(70, aH - suggY - 44)
    suggH := Min(suggH, maxSuggH)
    g.lblTips.Move(m, suggY - 24, fullW, 20)
    g.suggestions.Move(m, suggY, fullW, suggH)

    ; Status
    g.statText.Move(m, suggY + suggH + 12, fullW, 20)

    ; Refresh scaled display if image loaded
    if g.pOriginal
        UpdateDisplayImages(g, picW, picH)
}

UpdateDisplayImages(g, picW, picH) {
    if g.hOrigScaled {
        DllCall("DeleteObject", "Ptr", g.hOrigScaled)
        g.hOrigScaled := 0
    }
    if g.hSimScaled {
        DllCall("DeleteObject", "Ptr", g.hSimScaled)
        g.hSimScaled := 0
    }
    if g._sim3Scaled {
        for hb in g._sim3Scaled {
            if hb
                DllCall("DeleteObject", "Ptr", hb)
        }
    }
    g._sim3Scaled := []

    ; Scale original
    pScaled := GDI.ResizeBitmap(g.pOriginal, picW, picH)
    if pScaled {
        g.hOrigScaled := GDI.GetHBITMAP(pScaled)
        g.origPic.Value := "HBITMAP:" g.hOrigScaled
        GDI.DisposeImage(pScaled)
    }

    ; Check if 3-up mode is active
    is3Up := g.currentType = "All Three" && !g.chkHeat.Value
    if is3Up {
        ; Show 3-up, hide simPic
        g.simPic.Visible := false
        g.lblSimulated.Visible := false
        rowH := (picH - 24) // 3
        rowH := Max(50, rowH)
        loop 3 {
            yOff := (A_Index - 1) * (rowH + 8)
            g.sim3[A_Index].Visible := true
            g.lblSim3[A_Index].Visible := true
            g.sim3[A_Index].Move(, , picW, rowH)
        }
        ; Scale and set 3-up bitmaps
        for i, pSim in g._sim3Bitmaps {
            if pSim {
                pScaled3 := GDI.ResizeBitmap(pSim, picW, rowH)
                if pScaled3 {
                    hb := GDI.GetHBITMAP(pScaled3)
                    g._sim3Scaled.Push(hb)
                    g.sim3[i].Value := "HBITMAP:" hb
                    GDI.DisposeImage(pScaled3)
                }
            }
        }
    } else {
        ; Hide 3-up, show simPic
        loop 3 {
            g.sim3[A_Index].Visible := false
            g.lblSim3[A_Index].Visible := false
        }
        g.simPic.Visible := true
        g.lblSimulated.Visible := true

        ; Simulated/heatmap pane
        pSrc := g.pHeat ? g.pHeat : (g.pSimulated ? g.pSimulated : g.pOriginal)
        pScaled2 := GDI.ResizeBitmap(pSrc, picW, picH)
        if pScaled2 {
            g.hSimScaled := GDI.GetHBITMAP(pScaled2)
            g.simPic.Value := "HBITMAP:" g.hSimScaled
            GDI.DisposeImage(pScaled2)
        }
    }
}

BrowseFile(g) {
    file := FileSelect(1, , "Select Image", "Images (*.png; *.jpg; *.jpeg; *.bmp; *.tif; *.tiff; *.webp; *.gif)")
    if file = ""
        return
    LoadImage(g, file)
}

HandleDrop(g, files) {
    try {
        first := ""
        for file in files {
            first := file
            break
        }
        if first = ""
            return
        LoadImage(g, first)
    }
}

EnableDropFiles(g) {
    for ctrl in [g, g.origPic, g.simPic, g.report, g.suggestions] {
        try DllCall("shell32\DragAcceptFiles", "Ptr", ctrl.Hwnd, "Int", true)
    }
    for ctrl in g.sim3 {
        try DllCall("shell32\DragAcceptFiles", "Ptr", ctrl.Hwnd, "Int", true)
    }
}

OnDropFiles(wParam, lParam, msg, hwnd, g) {
    count := DllCall("shell32\DragQueryFileW", "Ptr", wParam, "UInt", 0xFFFFFFFF, "Ptr", 0, "UInt", 0)
    first := ""
    loop count {
        len := DllCall("shell32\DragQueryFileW", "Ptr", wParam, "UInt", A_Index - 1, "Ptr", 0, "UInt", 0)
        buf := Buffer((len + 1) * 2, 0)
        DllCall("shell32\DragQueryFileW", "Ptr", wParam, "UInt", A_Index - 1, "Ptr", buf, "UInt", len + 1)
        file := StrGet(buf, "UTF-16")
        if first = ""
            first := file
    }
    DllCall("shell32\DragFinish", "Ptr", wParam)
    if first != ""
        LoadImage(g, first)
    return 0
}

LoadImage(g, file) {
    ext := "." StrLower(SubStr(file, InStr(file, ".", 0, -1) + 1))
    static valid := ["png", "jpg", "jpeg", "bmp", "tif", "tiff", "webp", "gif"]
    ok := false
    for v in valid {
        if ext = "." v {
            ok := true
            break
        }
    }
    if !ok
        return

    ; Clean up previous
    ClearRegion(g)
    CleanupImage(g)

    GDI.Startup()
    g.currentFile := file
    SplitPath(file, &name)
    g.fileText.Value := name
    g.statText.Value := "Loading..."

    g.pOriginal := GDI.LoadImage(file)
    if !g.pOriginal {
        g.statText.Value := "Failed to load image."
        return
    }

    g.hOriginal := GDI.GetHBITMAP(g.pOriginal)

    g.currentType := "None"
    g._analysisCurrent := false
    g.report.Value := "Image loaded. Choose a mode, then press Start."
    g.suggestions.Value := ""
    g.lblSimulated.Text := "Simulation / Heatmap"
    SetProgress(g, 0, "Ready")
    g.origPic.GetPos(&oX, &oY, &oW, &oH)
    UpdateDisplayImages(g, oW, oH)
    g.statText.Value := "Loaded " name
}

RefreshAnalysis(g) {
    if !g.pOriginal {
        g.statText.Value := "No image loaded."
        return
    }
    if g._busy
        return
    g._busy := true
    g.btnRefresh.Enabled := false

    g.currentType := g.cbType.Text
    g.statText.Value := "Analyzing..."
    g._analysisCurrent := false
    SetProgress(g, 2, "Preparing...")

    ; Clean old resources
    ClearProcessedImages(g)

    ; Determine working bitmap (full or region)
    if g._regionW && g._regionH {
        pWork := GDI.CloneBitmapArea(g.pOriginal, g._regionX, g._regionY, g._regionW, g._regionH)
        if !pWork
            pWork := g.pOriginal
    } else
        pWork := g.pOriginal

    dims := GDI.GetDimensions(pWork)
    mode := g.currentType
    showHeat := g.chkHeat.Value

    ; Process based on mode
    is3Up := mode = "All Three" && !showHeat
    progressCb := (done, total) => SetProgress(g, 10 + (done / total * 62), "Filtering... " Round(done / total * 100) "%")
    if mode = "All Three" {
        ; Simulate all three types
        pSimC1 := CreateSimulatedBitmap(pWork, "Deuteranopia", (done, total) => SetProgress(g, 10 + (done / total * 20), "Filtering Deuteranopia..."))
        pSimC2 := CreateSimulatedBitmap(pWork, "Protanopia", (done, total) => SetProgress(g, 32 + (done / total * 20), "Filtering Protanopia..."))
        pSimC3 := CreateSimulatedBitmap(pWork, "Tritanopia", (done, total) => SetProgress(g, 54 + (done / total * 18), "Filtering Tritanopia..."))
        g._sim3Bitmaps := [pSimC1, pSimC2, pSimC3]
        g.lblSimulated.Text := "Deuteranopia / Protanopia / Tritanopia"

        if showHeat {
            SetProgress(g, 50, "Building average confusion map...")
            g.pHeat := BuildAverageConfusionMap(pWork, ["Deuteranopia", "Protanopia", "Tritanopia"])
            g.lblSimulated.Text := "Average confusion heatmap - All Three"
        }
    } else if mode = "Grayscale" {
        g.pSimulated := CreateGrayscaleBitmap(pWork, progressCb)
        g.hSimulated := GDI.GetHBITMAP(g.pSimulated)
        g.lblSimulated.Text := "Grayscale"
    } else if mode = "Luminance" {
        g.pSimulated := GDI.CloneImage(pWork)
        BuildLuminanceMap(g.pSimulated, progressCb)
        g.hSimulated := GDI.GetHBITMAP(g.pSimulated)
        g.lblSimulated.Text := "Luminance"
    } else if showHeat && IsColorblindMode(mode) {
        pSim := CreateSimulatedBitmap(pWork, mode, progressCb)
        SetProgress(g, 74, "Building confusion map...")
        g.pHeat := BuildConfusionMap(pWork, pSim, mode)
        GDI.DisposeImage(pSim)
        g.hSimulated := GDI.GetHBITMAP(g.pHeat)
        g.lblSimulated.Text := "Confusion heatmap - " mode
    } else if IsColorblindMode(mode) {
        g.pSimulated := CreateSimulatedBitmap(pWork, mode, progressCb)
        g.hSimulated := GDI.GetHBITMAP(g.pSimulated)
        g.lblSimulated.Text := mode
    } else {
        g.lblSimulated.Text := "No simulation"
    }

    ; Report uses region analysis if set
    SetProgress(g, 78, "Analyzing colors...")
    topColors := AnalyzeImageColors(pWork)
    typeStr := IsColorblindMode(mode) ? mode : ""
    g.report.Value := GenerateReport(topColors, typeStr)
    g.suggestions.Value := GenerateSuggestions(topColors, typeStr)

    ; Clean up region clone if made
    if pWork != g.pOriginal
        GDI.DisposeImage(pWork)

    ; Update scaled display
    SetProgress(g, 92, "Updating preview...")
    g.origPic.GetPos(&oX, &oY, &oW, &oH)
    UpdateDisplayImages(g, oW, oH)

    g._analysisCurrent := true
    SetProgress(g, 100, "Complete")
    g.statText.Value := "Done - " dims.w "x" dims.h " px"
    g.btnRefresh.Enabled := true
    g._busy := false
}

ShowGuide() {

    guideHwnd := WinExist("Colorblind-Friendly Palette Guide")

    if guideHwnd {
        guideGui := GuiFromHwnd(guideHwnd)
        guideGui.Show("Center")
        return
    }

    guideGui := Gui(
        "+AlwaysOnTop +ToolWindow",
        "Colorblind-Friendly Palette Guide"
    )

    guideGui.BackColor := "ffffff"

    guideGui.SetFont("s9", "Segoe UI")

    guideGui.MarginX := 12
    guideGui.MarginY := 10

    ; =====================================================
    ; HEADER
    ; =====================================================

    guideGui.SetFont("s12", "Segoe UI Semibold")

    guideGui.AddText(
        "xm c202020",
        "Colorblind-Friendly Color Palettes"
    )

    guideGui.SetFont("s9", "Segoe UI")

    guideGui.AddText(
        "xm y+4 c505050",
        "Palettes optimized for deuteranopia, protanopia, and tritanopia."
    )

    guideGui.AddText(
        "xm y+2 c6A6A6A",
        "Each palette includes distinguishable colors with hex/RGB references."
    )

    ; =====================================================
    ; TAB
    ; =====================================================

    tab := guideGui.AddTab3(
        "xm y+10 w700 h580 BackgroundFFFFFF c202020",
        ["2-3 Colors", "4-6 Colors", "8+ Palettes", "Tips"]
    )

    ; =====================================================
    ; TAB 1
    ; =====================================================

    tab.UseTab("2-3 Colors")

    guideGui.SetFont("s10", "Segoe UI Semibold")

    guideGui.AddText(
        "xm y+12 c1B6FA8",
        "2-Color Combinations"
    )

    guideGui.SetFont("s9", "Segoe UI")

    AddPaletteRow(
        guideGui,
        "Blue + Orange  (universal, all types)",
        [0x0077BB, 0xEE7733]
    )

    AddPaletteRow(
        guideGui,
        "Blue + Vermillion  (universal, all types)",
        [0x0077BB, 0xCC3311]
    )

    AddPaletteRow(
        guideGui,
        "Sky Blue + Orange  (good for all)",
        [0x88CCEE, 0xDDCC77]
    )

    guideGui.SetFont("s10", "Segoe UI Semibold")

    guideGui.AddText(
        "xm y+12 c1B6FA8",
        "3-Color Combinations"
    )

    guideGui.SetFont("s9", "Segoe UI")

    AddPaletteRow(
        guideGui,
        "Blue + Orange + Green",
        [0x0077BB, 0xEE7733, 0x009988]
    )

    AddPaletteRow(
        guideGui,
        "Blue + Vermillion + Teal",
        [0x0077BB, 0xCC3311, 0x44BB99]
    )

    AddPaletteRow(
        guideGui,
        "Dark Blue + Orange + Sky Blue",
        [0x004488, 0xEE9944, 0x88CCAA]
    )

    AddPaletteRow(
        guideGui,
        "Orange + Sky Blue + Magenta",
        [0xEE7733, 0x88CCEE, 0xEE3377]
    )

    ; =====================================================
    ; TAB 2
    ; =====================================================

    tab.UseTab("4-6 Colors")

    guideGui.SetFont("s10", "Segoe UI Semibold")

    guideGui.AddText(
        "xm y+12 c1B6FA8",
        "4-Color Combinations"
    )

    guideGui.SetFont("s9", "Segoe UI")

    AddPaletteRow(
        guideGui,
        "Blue + Orange + Green + Pink",
        [0x0077BB, 0xEE7733, 0x009988, 0xEE7788]
    )

    AddPaletteRow(
        guideGui,
        "Blue + Vermillion + Teal + Gold",
        [0x0077BB, 0xCC3311, 0x44BB99, 0xDDCC66]
    )

    guideGui.SetFont("s10", "Segoe UI Semibold")

    guideGui.AddText(
        "xm y+12 c1B6FA8",
        "5-Color Combination"
    )

    guideGui.SetFont("s9", "Segoe UI")

    AddPaletteRow(
        guideGui,
        "Blue + Orange + Green + Pink + Purple",
        [0x0077BB, 0xEE7733, 0x009988, 0xEE7788, 0xAA44DD]
    )

    guideGui.SetFont("s10", "Segoe UI Semibold")

    guideGui.AddText(
        "xm y+12 c1B6FA8",
        "6-Color Combination"
    )

    guideGui.SetFont("s9", "Segoe UI")

    AddPaletteRow(
        guideGui,
        "Blue + Orange + Green + Vermillion + Sky Blue + Magenta",
        [0x0077BB, 0xEE7733, 0x009988, 0xCC3311, 0x33BBEE, 0xEE3377]
    )

    ; =====================================================
    ; TAB 3
    ; =====================================================

    tab.UseTab("8+ Palettes")

    guideGui.SetFont("s10", "Segoe UI Semibold")

    guideGui.AddText(
        "xm y+12 c1B6FA8",
        "Wong 8-Color Palette"
    )

    guideGui.SetFont("s8", "Segoe UI")

    guideGui.AddText(
        "xm y+1 c808080",
        "Nature Methods (2011) — colorblind accessibility focused."
    )

    AddPaletteRow(
        guideGui,
        "Blue, Orange, Green, Vermillion, Sky Blue, Magenta, Grey, Yellow",
        [0x0077BB, 0xEE7733, 0x009988, 0xCC3311, 0x33BBEE, 0xEE3377, 0xBBBBBB, 0xDDCC77]
    )

    AddColorCodeTable(
        guideGui,
        [0x0077BB, 0xEE7733, 0x009988, 0xCC3311, 0x33BBEE, 0xEE3377, 0xBBBBBB, 0xDDCC77],
        ["Blue", "Orange", "Green", "Vermillion", "Sky Blue", "Magenta", "Grey", "Yellow"]
    )

    guideGui.SetFont("s10", "Segoe UI Semibold")

    guideGui.AddText(
        "xm y+14 c1B6FA8",
        "Okabe & Ito 8-Color Palette"
    )

    guideGui.SetFont("s8", "Segoe UI")

    guideGui.AddText(
        "xm y+1 c808080",
        "Designed for scientific figures and presentations."
    )

    AddColorCodeTable(
        guideGui,
        [0x000000, 0xE69F00, 0x56B4E9, 0x009E73, 0xF0E442, 0x0072B2, 0xD55E00, 0xCC79A7],
        ["Black", "Orange", "Sky Blue", "Green", "Yellow", "Blue", "Vermillion", "Pink"]
    )

    guideGui.SetFont("s10", "Segoe UI Semibold")

    guideGui.AddText(
        "xm y+14 c1B6FA8",
        "Tol 10-Color Palette"
    )

    guideGui.SetFont("s8", "Segoe UI")

    guideGui.AddText(
        "xm y+1 c808080",
        "Optimized for printability and accessibility."
    )

    AddColorCodeTable(
        guideGui,
        [0x332288, 0x117733, 0x44AA99, 0x88CCEE, 0xDDCC77, 0xCC6677, 0xAA4499, 0x88CCAA, 0x661100, 0x6699CC],
        ["Indigo", "Green", "Teal", "Sky Blue", "Yellow", "Rose", "Purple", "Teal 2", "Brown", "Blue"]
    )

    ; =====================================================
    ; TAB 4
    ; =====================================================

    tab.UseTab("Tips")

    tips :=
    "
(
General Accessibility Tips

1. Use contrast, not only color
   Add labels, icons, or patterns.

2. Use texture patterns
   Dots, stripes, hatchings help readability.

3. Use symbols & markers
   ◼ ● ▲ ◆ improve differentiation.

4. Use labels directly
   Avoid relying only on legends.

5. Use line styles
   Solid, dashed, dotted, dash-dot.

6. Avoid red/green combinations
   Commonly problematic.

7. Prefer blue/orange combinations
   Safest universal distinction.

8. Check WCAG contrast
   Aim for 4.5:1 minimum.

9. Test your palette
   Use simulation preview tools.

10. Add redundant cues
    Shape, size, labels, and icons help accessibility.

Recommended Pairs:
  • Blue + Orange
  • Black + Yellow
  • Purple + Yellow
  • Blue + Red
)"
    
    guideGui.AddEdit(
        "xm y+12 w660 h430 ReadOnly BackgroundFFFFFF c202020",
        tips
    )

    ; =====================================================
    ; FOOTER
    ; =====================================================

    tab.UseTab()

    btnClose := guideGui.AddButton(
        "x592 y668 w100 h28",
        "Close"
    )

    btnClose.OnEvent(
        "Click",
        (*) => guideGui.Destroy()
    )

    guideGui.Show("w730 h730 Center")
}

AddPaletteRow(g, label, colors) {
    g.SetFont("s9", "Segoe UI")
    g.AddText("xm y+8 w660 c303030", label)
    baseX := 20
    hexRow := ""
    rgbRow := ""
    for c in colors {
        hex := SubStr(Format("{:#06X}", c), 3)
        r := (c >> 16) & 0xFF
        g_ := (c >> 8) & 0xFF
        b := c & 0xFF
        if A_Index = 1
            g.AddText("xm+" baseX " y+4 w40 h18 Background" hex, Chr(160))
        else
            g.AddText("x+48 yp w40 h18 Background" hex, Chr(160))
        hexRow .= "  #" hex "  "
        rgbRow .= "RGB(" Format("{:03d},{:03d},{:03d}", r, g_, b) ")  "
    }
    g.AddText("xm+" baseX " y+4 w660 c5A5A5A", Trim(hexRow))
    g.AddText("xm+" baseX " y+2 w660 c3A3A3A", Trim(rgbRow))
}

AddColorCodeTable(g, colors, names) {
    startY := "y+6"
    for i, c in colors {
        hex := SubStr(Format("{:#06X}", c), 3)
        r := (c >> 16) & 0xFF
        g_ := (c >> 8) & 0xFF
        b := c & 0xFF
        rgbStr := Format("{:03d},{:03d},{:03d}", r, g_, b)
        name := names.Length >= i ? names[i] : ""

        yExpr := i = 1 ? startY : "y+2"
        g.AddText("xm " yExpr " w20 h16 Background" hex " c" hex, Chr(160))
        g.AddText("x+6 yp-3 w70 c000000", name)
        g.AddText("x+4 yp w55 c555555", "#" hex)
        g.AddText("x+2 yp w90 c333333", "RGB(" rgbStr ")")
    }
}

CleanupImage(g) {
    if g.hOriginal {
        try DllCall("DeleteObject", "Ptr", g.hOriginal)
        g.hOriginal := 0
    }
    if g.hSimulated {
        try DllCall("DeleteObject", "Ptr", g.hSimulated)
        g.hSimulated := 0
    }
    if g.hOrigScaled {
        try DllCall("DeleteObject", "Ptr", g.hOrigScaled)
        g.hOrigScaled := 0
    }
    if g.hSimScaled {
        try DllCall("DeleteObject", "Ptr", g.hSimScaled)
        g.hSimScaled := 0
    }
    if g._sim3Scaled {
        for hb in g._sim3Scaled {
            if hb
                try DllCall("DeleteObject", "Ptr", hb)
        }
        g._sim3Scaled := []
    }
    if g.pOriginal {
        GDI.DisposeImage(g.pOriginal)
        g.pOriginal := 0
    }
    if g.pSimulated {
        GDI.DisposeImage(g.pSimulated)
        g.pSimulated := 0
    }
    if g.pHeat {
        GDI.DisposeImage(g.pHeat)
        g.pHeat := 0
    }
    if g._sim3Bitmaps {
        for p in g._sim3Bitmaps {
            if p
                GDI.DisposeImage(p)
        }
        g._sim3Bitmaps := []
    }
}

AppExit(*) {
    global APP_GUI
    if APP_GUI {
        try CleanupImage(APP_GUI)
        try APP_GUI.Destroy()
        APP_GUI := 0
    }
    GDI.Shutdown()
}

; ===================================================================
; Entry
; ===================================================================
OnExit(AppExit)
BuildGui()
