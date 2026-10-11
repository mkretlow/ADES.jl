# Element tables derived from the ADES general schema (IAU-ADES/ADES-Master, xsd/general.xsd).

"""
    RECORD_KINDS

The ADES observation record types: `:optical`, `:offset`, `:occultation` and `:radar`
appear inside an `obsBlock`; `:opticalResidual` and `:radarResidual` appear only at the
top level of distribution files.
"""
const RECORD_KINDS = (:optical, :offset, :occultation, :radar, :opticalResidual, :radarResidual)

const _OPTICAL_ID = [:permID, :provID, :artSat, :trkSub, :obsID, :obsSubID, :trkID, :trkMPC]
const _RADAR_ID = [:permID, :provID, :artSat, :trkSub, :obsID]
const _LOCATION = [:sys, :ctr, :pos1, :pos2, :pos3, :vel1, :vel2, :vel3,
                   :posCov11, :posCov12, :posCov13, :posCov22, :posCov23, :posCov33]
const _PHOTOMETRY = [:mag, :rmsMag, :band, :fltr, :photCat, :photAp, :nucMag]
const _OFFSET_VAL = [:deltaRA, :deltaDec, :rmsRA, :rmsDec, :rmsCorr, :dist, :pa, :rmsDist, :rmsPA]
const _PRECISION = [:precTime, :precRA, :precDec]
const _OPTICAL_RESIDUALS = [:orbProd, :orbID, :resRA, :resDec, :selAst, :sigRA, :sigDec,
                            :sigCorr, :sigTime, :biasRA, :biasDec, :biasTime,
                            :photProd, :resMag, :selPhot, :sigMag, :biasMag, :photMod]
const _RADAR_RESIDUALS = [:orbProd, :orbID, :resDelay, :selDelay, :sigDelay,
                          :resDoppler, :selDoppler, :sigDoppler]

"""
    ELEMENT_ORDER

Schema order of the elements of each record kind. XML output follows this order, since
the ADES schema uses `xsd:sequence`.
"""
const ELEMENT_ORDER = Dict{Symbol,Vector{Symbol}}(
    :optical => [_OPTICAL_ID; :mode; :stn; _LOCATION; :prog; :obsTime; :rmsTime;
                 :ra; :dec; :rmsRA; :rmsDec; :rmsCorr; :astCat; _PHOTOMETRY;
                 :logSNR; :seeing; :exp; :rmsFit; :nStars; :ref; :disc; :subFrm; :subFmt;
                 _PRECISION; :uncTime; :notes; :remarks; _OPTICAL_RESIDUALS;
                 :deprecated; :localUse],
    :offset => [_OPTICAL_ID; :mode; :stn; _LOCATION; :prog; :obsTime; :rmsTime;
                :obsCenter; _OFFSET_VAL; _PHOTOMETRY;
                :logSNR; :seeing; :exp; :rmsFit; :nStars; :ref; :disc; :subFrm; :subFmt;
                _PRECISION; :uncTime; :notes; :remarks; _OPTICAL_RESIDUALS;
                :deprecated; :localUse],
    :occultation => [_OPTICAL_ID; :mode; :stn; _LOCATION; :prog; :obsTime; :rmsTime;
                     :raStar; :decStar; _OFFSET_VAL; :astCat; _PHOTOMETRY;
                     :logSNR; :shapeOcc; :seeing; :ref; :disc; :subFrm; :subFmt;
                     _PRECISION; :uncTime; :notes; :remarks; _OPTICAL_RESIDUALS;
                     :deprecated; :localUse],
    :radar => [_RADAR_ID; :trx; :rcv; :prog; :obsTime; :doppler; :rmsDoppler; :delay; :rmsDelay;
               :logSNR; :com; :frq; :ref; :remarks; _RADAR_RESIDUALS; :localUse],
    :opticalResidual => [_OPTICAL_ID; :obsTime; _OPTICAL_RESIDUALS],
    :radarResidual => [_RADAR_ID; :obsTime; _RADAR_RESIDUALS],
)

"""
    REQUIRED_ELEMENTS

Elements every record of a kind must carry. An identifier (`permID`, `provID`, `artSat`
or `trkSub`) is required too; [`validate`](@ref) checks that separately.
"""
const REQUIRED_ELEMENTS = Dict{Symbol,Vector{Symbol}}(
    :optical => [:mode, :stn, :obsTime, :ra, :dec, :astCat],
    :offset => [:mode, :stn, :obsTime, :obsCenter],
    :occultation => [:mode, :stn, :obsTime, :raStar, :decStar, :astCat],
    :radar => [:trx, :rcv, :obsTime, :frq],
    :opticalResidual => [:obsTime, :orbProd, :orbID],
    :radarResidual => [:obsTime, :orbProd, :orbID],
)

const _FLOAT_ELEMENTS = Set([
    :pos1, :pos2, :pos3, :vel1, :vel2, :vel3,
    :posCov11, :posCov12, :posCov13, :posCov22, :posCov23, :posCov33,
    :rmsTime, :ra, :dec, :raStar, :decStar, :deltaRA, :deltaDec, :dist, :pa,
    :rmsRA, :rmsDec, :rmsDist, :rmsPA, :rmsCorr, :delay, :rmsDelay, :doppler, :rmsDoppler,
    :mag, :rmsMag, :photAp, :logSNR, :seeing, :exp, :rmsFit, :frq, :precRA, :precDec,
    :uncTime, :resRA, :resDec, :sigRA, :sigDec, :sigCorr, :sigTime, :biasRA, :biasDec,
    :biasTime, :resMag, :sigMag, :biasMag, :resDelay, :sigDelay, :resDoppler, :sigDoppler,
])
const _INT_ELEMENTS = Set([:ctr, :nStars, :nucMag, :shapeOcc, :com, :precTime])

"""
    element_type(name::Symbol) -> Type

Julia type that the value of ADES element `name` is parsed into: `Float64`, `Int`,
`DateTime` (for `obsTime`) or `String`.
"""
function element_type(name::Symbol)
    name in _FLOAT_ELEMENTS && return Float64
    name in _INT_ELEMENTS && return Int
    name === :obsTime && return DateTime
    return String
end

# Infer the record kind from the set of column names in a PSV keyword line.
function _infer_kind(cols)
    s = Set(cols)
    (:trx in s || :delay in s || :doppler in s) && return :radar
    (:resDelay in s || :resDoppler in s) && return :radarResidual
    :raStar in s && return :occultation
    :obsCenter in s && return :offset
    :ra in s && return :optical
    :resRA in s && return :opticalResidual
    return :optical
end
