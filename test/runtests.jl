using PDFIO
using PDFIO.PD
using PDFIO.Cos
using PDFIO.Common
using Base.Test

using PDFIO.Cos: parse_indirect_ref

include("debugIO.jl")

@testset "PDFIO tests" begin

    @testset "Miscellaneous" begin
        @test string(CDDate("D : 199812231952 - 08' 30 "))==
            "1998-12-23T19:52:00 - 8 hours, 30 minutes"
        @test_throws ErrorException skipv(IOBuffer([UInt8(65), UInt8(66)]),
                                          UInt8(66))
        @test CDTextString(PDFIO.Cos.CosXString([UInt8('0'), UInt8('0'),
                                                 UInt8('4'),UInt8('1')]))=="A"
        @test CosFloat(CosInt(1)) == CosFloat(1f0)
        @test [CosFloat(1f0), CosInt(2)] == [CosFloat(1f0), CosFloat(2f0)]
        @test CDRect(CosArray([CosInt(0),
                               CosInt(0),
                               CosInt(640),
                               CosInt(480)])) == CDRect(0, 0, 640, 480)
        @test parse_indirect_ref(IOBuffer(Vector{UInt8}("10 0 R\n"))) ==
            CosIndirectObjectRef(10, 0)
    end
    @testset "Test FlateDecode" begin
        @test begin
            filename="files/1.pdf"
            println(filename)
            doc = pdDocOpen(filename)
            println(pdDocGetCatalog(doc))
            cosDoc = pdDocGetCosDoc(doc)
            map(println, cosDoc.trailer)
            info = pdDocGetInfo(doc)
            @assert info["Producer"] == "LibreOffice 5.3" && info["Creator"] == "Writer"
            @assert pdDocGetPageCount(doc) == 2
            page = pdDocGetPage(doc, 1)
            @assert pdPageIsEmpty(page) == false
            contents = pdPageGetContents(page)
            bufstm = get(contents)
            buf = read(bufstm)
            close(bufstm)
            @assert length(buf) == 18669
            @assert length(pdPageGetContentObjects(page).objs)==190
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "PDF File with ObjectStreams" begin
        @test begin
            filename="files/pdf-17.pdf"
            DEBUG && println(filename)
            doc = pdDocOpen(filename)
            @assert pdDocGetPageCount(doc) == 1
            page = pdDocGetPage(doc, 1)
            @assert pdPageIsEmpty(page) == false
            contents = pdPageGetContents(page)
            bufstm = get(contents)
            buf = read(bufstm)
            close(bufstm)
            @assert length(buf) == 1021
            @assert length(pdPageGetContentObjects(page).objs)==1
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "General File Opening 3" begin
        @test begin
            filename="3.pdf"
            DEBUG && println(filename)
            isfile(filename)||
                download("http://www.stillhq.com/pdfdb/000003/data.pdf",filename)
            doc = pdDocOpen(filename)
            @assert pdDocGetPageCount(doc) == 30
            page = pdDocGetPage(doc, 1)
            @assert pdPageIsEmpty(page) == false
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Hybrid x-ref" begin
        @test begin
            filename="A1947-15.pdf"
            DEBUG && println(filename)
            isfile(filename)||
                download("http://indiacode.nic.in/bitstream/123456789/1419/1/194715.pdf",filename)
            doc = pdDocOpen(filename)
            resfile, template = testfiles(filename)
            io = util_open(resfile, "w")
            try
                extract_text(io, doc)
            finally
                util_close(io)
                pdDocClose(doc)
            end
            @assert files_equal(resfile, template)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Corrupt File" begin
        @test begin
            filename="A1947-14.pdf"
            DEBUG && println(filename)
            isfile(filename)||
                download("http://indiacode.nic.in/bitstream/123456789/2169/1/A1947-14.pdf",filename)
            doc = pdDocOpen(filename)
            try
                npage= pdDocGetPageCount(doc)
                for i=1:npage
                    page = pdDocGetPage(doc, i)
                    if pdPageIsEmpty(page) == false
                        pdPageGetContentObjects(page)
                        pdPageExtractText(IOBuffer(), page)
                    end
                end
            finally
                pdDocClose(doc)
            end
            length(utilPrintOpenFiles()) == 0
        end
    end


    @testset "Test RunLengthDecode" begin
        @test begin
            filename="582.pdf"
            DEBUG && println(filename)
            isfile(filename)||
                download("http://www.stillhq.com/pdfdb/000582/data.pdf",filename)
            doc = pdDocOpen(filename)
            @assert pdDocGetPageCount(doc) == 12
            obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc,
                                          PDFIO.Cos.CosIndirectObjectRef(177, 0))
            stm=get(obj)
            data=read(stm)
            close(stm)
            @assert length(data) == 273
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Test ASCIIHexDecode" begin
        @test begin
        filename="325.pdf"
        DEBUG && println(filename)
        isfile(filename)||
            download("http://www.stillhq.com/pdfdb/000325/data.pdf",filename)
        doc = pdDocOpen(filename)
        @assert pdDocGetPageCount(doc) == 1
        obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc, PDFIO.Cos.CosIndirectObjectRef(7, 0))
        stm=get(obj)
        data=read(stm)
        close(stm)
        @assert length(data) == 121203
        pdDocClose(doc)
        length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Test ASCII85Decode" begin
        @test begin
        filename="388.pdf"
        DEBUG && println(filename)
        isfile(filename)||
            download("http://www.stillhq.com/pdfdb/000388/data.pdf",filename)
        doc = pdDocOpen(filename)
        @assert pdDocGetPageCount(doc) == 1
        obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc, PDFIO.Cos.CosIndirectObjectRef(9, 0))
        stm=get(obj)
        data=read(stm)
        close(stm)
        @assert length(data) == 38117
        pdDocClose(doc)
        length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "LZWDecode Filter" begin
        @test begin
            filename="589.pdf"
            DEBUG && println(filename)
            isfile(filename)||
                download("http://www.stillhq.com/pdfdb/000589/data.pdf",filename)
            doc = pdDocOpen(filename)
            obj=PDFIO.Cos.cosDocGetObject(doc.cosDoc, PDFIO.Cos.CosIndirectObjectRef(70, 0))
            stm=get(obj)
            data=read(stm)
            close(stm)
            @assert length(data) == 768
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    
    @testset "Test read_string" begin
        @test begin
            DEBUG && PDFIO.Cos.parse_data("files/page5.txt")
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Page label test" begin
        @test begin
            filename="431.pdf"
            DEBUG && println(filename)
            isfile(filename) ||
                download("http://www.stillhq.com/pdfdb/000431/data.pdf",filename)
            doc = pdDocOpen(filename)
            @assert pdDocGetPageCount(doc) == 54
            @assert PDFIO.Cos.cosDocGetPageNumbers(doc.cosDoc, doc.catalog, "title") ==
                range(1,1)
            @assert PDFIO.Cos.cosDocGetPageNumbers(doc.cosDoc, doc.catalog, "ii") ==
                range(3,1)
            @assert PDFIO.Cos.cosDocGetPageNumbers(doc.cosDoc, doc.catalog, "42") ==
                range(46,1)
            pdDocGetPageRange(doc, "iii")
            pdDocClose(doc)
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Symbol Fonts test" begin
        @test begin
            filename="431.pdf"
            result, template_file = local_testfiles(filename)
            DEBUG && println(filename)
            isfile(filename) ||
                download("http://www.stillhq.com/pdfdb/000431/data.pdf",filename)
            doc = pdDocOpen(filename)
            (npage = pdDocGetPageCount(doc)) == 54
            try
                open(result, "w") do io
                    for i=1:npage
                        page = pdDocGetPage(doc, i)
                        if pdPageIsEmpty(page) == false
                            pdPageGetContentObjects(page)
                            pdPageExtractText(io, page)
                        end
                    end
                end
                @assert files_equal(result, template_file)
            finally
                pdDocClose(doc)
            end
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "Inline Image test" begin
        @test begin
            filename="Pratham-Sanskaran.pdf"
            result, template_file, src = local_testfiles(filename)
            DEBUG && println(src)
            doc = pdDocOpen(src)
            (npage = pdDocGetPageCount(doc)) == 3
            try
                open(result, "w") do io
                    for i=1:npage
                        page = pdDocGetPage(doc, i)
                        if pdPageIsEmpty(page) == false
                            pdPageGetContentObjects(page)
                            pdPageExtractText(io, page)
                        end
                    end
                end
                @assert files_equal(result, template_file)
            finally
                pdDocClose(doc)
            end
            length(utilPrintOpenFiles()) == 0
        end
    end

    @testset "MacRomanEncoding Fonts test" begin
        @test begin
            filename="spec-2.pdf"
            result, template_file, src = local_testfiles(filename)
            DEBUG && println(src)
            doc = pdDocOpen(src)
            @assert (npage = pdDocGetPageCount(doc)) == 1
            try
                open(result, "w") do io
                    for i=1:npage
                        page = pdDocGetPage(doc, i)
                        if pdPageIsEmpty(page) == false
                            pdPageGetContentObjects(page)
                            pdPageExtractText(io, page)
                        end
                    end
                end
                @assert files_equal(result, template_file)
            finally
                pdDocClose(doc)
            end
            length(utilPrintOpenFiles()) == 0
        end
    end
    files=readdir(get_tempdir())
    @assert length(files) == 0
end

if isfile("pvt/pvttests.jl")
    include("pvt/pvttests.jl")
end
