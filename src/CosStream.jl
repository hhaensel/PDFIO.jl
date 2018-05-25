import Base: eof

export  cosStreamRemoveFilters,
        merge_streams,
        decode

_not_implemented(input, params) = error(E_NOT_IMPLEMENTED)

include("Inflate.jl")

"""
Decodes using the LZWDecode compression
"""
function decode_lzw(input, parms)
    if parms !== CosNull 
        earlyChange = get(parms, cn"EarlyChange")
        early = earlyChange === CosNull ? 1 : get(earlyChange)
    else
        early = 1
    end
    io = decode_lzw(input, early)
    util_close(input)
    return apply_flate_params(io, parms)
end

function decode_flate(input, parms)
    io = inflate(input)
    util_close(input)
    return apply_flate_params(io, parms)
end

apply_flate_params(input, parms) = input

decode_asciihex(input::IO, parms) = decode_asciihex(input)

decode_ascii85(input::IO, parms) = decode_ascii85(input)

decode_rle(input::IO, parms) = decode_rle(input)

const function_map = Dict(
                          cn"ASCIIHexDecode" => decode_asciihex,
                          cn"ASCII85Decode" => decode_ascii85,
                          cn"LZWDecode" => decode_lzw,
                          cn"FlateDecode" => decode_flate,
                          cn"RunLengthDecode" => decode_rle,
                          cn"CCITTFaxDecode" => _not_implemented,
                          cn"JBIG2Decode" => _not_implemented,
                          cn"DCTDecode" => _not_implemented,
                          cn"JPXDecode" => _not_implemented,
                          cn"Crypt" => _not_implemented
                         )

function cosStreamRemoveFilters(stm::CosObject)
    filters = get(stm, CosName("FFilter"))
    if (filters != CosNull)
        bufstm = decode(stm)
        data = read(bufstm)
        util_close(bufstm)
        filename = get(stm, CosName("F"))
        write(filename |> get |> String, data)
        set!(stm, CosName("FFilter"), CosNull)
    end
    return stm
end

function merge_streams(stms::CosArray)
    (path,io) = get_tempfilepath()
    try
        dict = CosDict()
        set!(dict, cn"F", CosLiteralString(path))
        ret = CosStream(dict, false)
        v = get(stms)
        for stm in v
            bufstm = decode(stm)
            data = read(bufstm)
            util_close(bufstm)
            write(io, data)
        end
        return ret
    finally
        util_close(io)
    end
    return CosNull
end

"""
Reads the filter data and decodes the stream.
"""
function decode(stm::CosObject)
    filename = get(stm, cn"F")
    filters =  get(stm, cn"FFilter")
    parms =    get(stm, cn"FDecodeParms")

    io = util_open(String(filename), "r")

    return decode_filter(io, filters, parms)
end

decode_filter(io, filter::CosNullType, parms::CosObject) = io

decode_filter(io, filter::CosName, parms::CosObject) =
    function_map[filter](io, parms)

function decode_filter(io, filters::CosArray, parms::CosObject)
    bufstm = io
    for filter in get(filters)
        bufstm = decode_filter(bufstm, filter, parms)
    end
    return bufstm
end

function apply_flate_params(input::IO, parms::CosDict)
    predictor        = get(parms, cn"Predictor")
    colors           = get(parms, cn"Colors")
    bitspercomponent = get(parms, cn"BitsPerComponent")
    columns          = get(parms, cn"Columns")

    predictor_n        = (predictor !== CosNull) ? get(predictor) : 0
    colors_n           = (colors !== CosNull) ?    get(colors) : 0
    bitspercomponent_n = (bitspercomponent !== CosNull) ?
                              get(bitspercomponent) : 0
    columns_n          = (columns !== CosNull) ? get(columns) : 0

    return (predictor_n == 2)  ? error(E_NOT_IMPLEMENTED) :
           (predictor_n >= 10) ? apply_flate_params(input, predictor_n - 10,
                                                    columns_n) : input
end


# Exactly as stated in https://www.w3.org/TR/PNG-Filters.html
@inline function PaethPredictor(a, b, c)
    # a = left, b = above, c = upper left
    p = a + b - c        # initial estimate
    pa = abs(p - a)      # distances to a, b, c
    pb = abs(p - b)
    pc = abs(p - c)
    # return nearest of a,b,c,
    # breaking ties in order a,b,c.
    return  (pa <= pb && pa <= pc) ? a :
                        (pb <= pc) ? b :
                                     c
end

@inline function png_predictor_rule(curr, prev, n, row, rule)
    if rule == 0
        copy!(curr, 1, row, 2, n)
    elseif rule == 1
        curr[1] = row[2]
        for i=2:n
            curr[i] = curr[i-1] + row[i+1]
        end
    elseif rule == 2
        for i=1:n
            curr[i] = prev[i] + row[i+1]
        end
    elseif rule == 3
        curr[1] = prev[1] + row[2]
        for i=2:n
            avg = div(curr[i-1] + prev[i], 2)
            curr[i] = avg + row[i+1]
        end
    elseif (rule == 4)
        curr[1] = prev[1] + row[2]
        for i=2:n
            pred = PaethPredictor(curr[i-1], prev[i], prev[i-1])
            curr[i] = pred + row[i+1]
        end
    end
end

function apply_flate_params(io::IO, pred::Int, col::Int)
    iob = IOBuffer()
    incol = col + 1
    curr = zeros(UInt8, col)
    prev = zeros(UInt8, col)
    nline = 0
    while !eof(io)
        row = read(io, incol)
        @assert (pred != 5) && (row[1] == pred)
        nline >= 1 && copy!(prev, curr)
        png_predictor_rule(curr, prev, col, row, row[1])
        write(iob, curr)
        nline += 1
    end
    util_close(io)
    return seekstart(iob)
end

function decode_rle(input::IO)
    iob = IOBuffer()
    b = read(input, UInt8)
    a = Vector{UInt8}(256)
    while !eof(input)
        b == 0x80 && break
        if b < 0x80
            resize!(a, b + 1)
            nb = readbytes!(input, a, b + 1)
            resize!(a, nb)
            write(iob, a)
        else
            c = read(input, UInt8)
            write(iob, fill(c, 257 - b))
        end
        b = read(input, UInt8)
    end
    util_close(input)
    return seekstart(iob)
end

# This function is very tolerant as a hex2bytes converter
# It rejects any bytes less than '0' so that control characters
# are ignored. Any character above '9' it sanitizes to a number
# under 0xF. PDF Spec also does not mandate the stream to have
# even number of values. If odd number of hexits are given '0'
# has to be appended to th end.

function decode_asciihex(input::IO)
    data = read(input)
    nb = length(data)
    B0 = UInt8('0')
    B9 = UInt8('9')
    j = 0
    k = true
    for i = 1:nb
        @inbounds b = data[i]
        b < B0 && continue
        c = b > B9 ? ((b & 0x07) + 0x09) : (b & 0x0F)
        if k 
            data[j+=1] = c << 4
        else
            data[j] += c
        end
        k = !k
    end
    util_close(input)
    resize!(data, j)
    return IOBuffer(data)
end

function _extend_buffer!(data, nb, i, j)
    SLIDE = 1024
    if j + 4 > i
        resize!(data, nb + SLIDE)
        copy!(data, i + 1 + SLIDE, data, i + 1, nb - i)
        nb += SLIDE
         i += SLIDE
    end
    return nb, i
end

function decode_ascii85(input::IO)
    data = read(input)
    nb = length(data)
    i = j = k = 0
    n::UInt32 = 0
    while i < nb
        b = data[i+=1]
        if b == LATIN_Z
            k > 0 && error(E_UNEXPECTED_CHAR)
            nb, i = _extend_buffer!(data, nb, i, j)
            for ii=1:4
                data[j+=1] = 0x0
            end
        elseif b == TILDE
            c = data[i+=1]
            i <= nb && c == GREATER_THAN && break
        elseif ispdfspace(b)
            k = 0
            n = 0
        elseif BANG <= b <= LATIN_U
            v = b - BANG
            n *= 85
            n += v
            k = k == 4 ? 0 : (k + 1)
            if k == 0
                for l=4:-1:1
                    data[j+l] = UInt8(n & 0xff)
                    n >>= 8
                end
                j += 4
                n = 0
            end
        else
            error(E_UNEXPECTED_CHAR)
        end
    end
    if k > 0
        for kk = k:4
            n *= 85
        end
        for l=4:-1:1
            l <= k && (data[j+l] = UInt8(n & 0xff))
            n >>= 8
        end
        j += (k - 1)
    end
    util_close(input)
    resize!(data, j)
    return IOBuffer(data)
end
