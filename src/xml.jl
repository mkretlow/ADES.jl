# ADES XML reading and writing

"""
    read_xml(source) -> ADESData

Read an ADES XML file. `source` is a file path or an `IO`. Use [`parse_xml`](@ref)
for a string.
"""
read_xml(path::AbstractString) = _from_xml(EzXML.readxml(path))
read_xml(io::IO) = parse_xml(read(io, String))

"""
    parse_xml(str::AbstractString) -> ADESData

Parse ADES XML held in a string.
"""
parse_xml(str::AbstractString) = _from_xml(EzXML.parsexml(str))

_elements(node) = EzXML.eachelement(node)
_text(node) = strip(EzXML.nodecontent(node))

function _from_xml(doc::EzXML.Document)
    root = EzXML.root(doc)
    EzXML.nodename(root) == "ades" ||
        throw(ArgumentError("not an ADES document: root element is <$(EzXML.nodename(root))>"))
    version = haskey(root, "version") ? root["version"] : ""
    blocks = ObsBlock[]
    loose = nothing        # block collecting records outside any obsBlock
    for node in _elements(root)
        name = EzXML.nodename(node)
        if name == "obsBlock"
            push!(blocks, _read_obsblock(node))
            loose = nothing
        elseif Symbol(name) in RECORD_KINDS
            if loose === nothing
                loose = ObsBlock(nothing, Observation[])
                push!(blocks, loose)
            end
            push!(loose.observations, _read_record(node))
        else
            @warn "ADES: ignoring unexpected top-level element <$name>"
        end
    end
    return ADESData(version, blocks)
end

function _read_obsblock(node)
    ctx = nothing
    obs = Observation[]
    for child in _elements(node)
        name = EzXML.nodename(child)
        if name == "obsContext"
            ctx = _read_context(child)
        elseif name == "obsData"
            for rec in _elements(child)
                push!(obs, _read_record(rec))
            end
        end
    end
    return ObsBlock(ctx, obs)
end

function _read_context(node)
    ctx = ObsContext()
    for sec in _elements(node)
        entries = [EzXML.nodename(e) => String(_text(e)) for e in _elements(sec)]
        value = isempty(entries) ? String(_text(sec)) : ""
        push!(ctx, ContextSection(EzXML.nodename(sec), value, entries))
    end
    return ctx
end

function _read_record(node)
    kind = Symbol(EzXML.nodename(node))
    kind in RECORD_KINDS || throw(ArgumentError("unknown ADES record <$kind>"))
    fields = Dict{Symbol,String}()
    for el in _elements(node)
        name = Symbol(EzXML.nodename(el))
        # localUse holds arbitrary XML; keep it verbatim so it can be written back
        fields[name] = name === :localUse ? string(_strip_blanks!(el)) : String(_text(el))
    end
    return Observation(kind, fields)
end

# Remove whitespace-only text nodes, so that indentation added by pretty-printing does
# not change the stored localUse content.
function _strip_blanks!(node)
    for child in collect(EzXML.eachnode(node))
        if EzXML.istext(child) && isempty(strip(EzXML.nodecontent(child)))
            EzXML.unlink!(child)
        elseif EzXML.iselement(child)
            _strip_blanks!(child)
        end
    end
    return node
end

"""
    write_xml(dest, data::ADESData)

Write `data` as ADES XML to `dest` (a file path or an `IO`). Elements are written in
the order the ADES schema requires.
"""
function write_xml(io::IO, d::ADESData)
    doc = EzXML.XMLDocument()
    root = EzXML.ElementNode("ades")
    EzXML.setroot!(doc, root)
    root["version"] = isempty(d.version) ? "2022" : d.version
    for b in d.blocks
        if b.context === nothing
            for o in b.observations
                _write_record(root, o)
            end
        else
            blk = EzXML.addelement!(root, "obsBlock")
            ctx = EzXML.addelement!(blk, "obsContext")
            for s in b.context.sections
                if isempty(s.entries)
                    EzXML.addelement!(ctx, s.name, s.value)
                else
                    sec = EzXML.addelement!(ctx, s.name)
                    for (k, v) in s.entries
                        EzXML.addelement!(sec, k, v)
                    end
                end
            end
            data = EzXML.addelement!(blk, "obsData")
            for o in b.observations
                _write_record(data, o)
            end
        end
    end
    EzXML.prettyprint(io, doc)
    println(io)
    return nothing
end
write_xml(path::AbstractString, d::ADESData) = open(io -> write_xml(io, d), path, "w")

"""
    xml_string(data::ADESData) -> String

`data` rendered as ADES XML.
"""
xml_string(d::ADESData) = sprint(write_xml, d)

function _write_record(parent, o::Observation)
    rec = EzXML.addelement!(parent, string(o.kind))
    for k in _ordered_keys(o)
        v = _fields(o)[k]
        if k === :localUse
            frag = EzXML.root(EzXML.parsexml(v))
            EzXML.link!(rec, EzXML.unlink!(frag))
        else
            EzXML.addelement!(rec, string(k), v)
        end
    end
end

# Keys of an observation in schema order, with unknown elements before localUse.
function _ordered_keys(o::Observation)
    order = ELEMENT_ORDER[o.kind]
    ks = [k for k in order if haskey(o, k) && k !== :localUse]
    append!(ks, sort!([k for k in keys(_fields(o)) if !(k in order)]))
    haskey(o, :localUse) && push!(ks, :localUse)
    return ks
end
