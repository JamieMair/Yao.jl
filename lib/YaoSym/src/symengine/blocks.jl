op_types = [:Mul, :Add, :Pow]
const BiVarOp = Union{[SymEngine.BasicType{Val{i}} for i in op_types]...}

simag = SymFunction("Im")
sreal = SymFunction("Re")
sangle = SymFunction("angle")

Base.promote_rule(::Type{Bool}, ::Type{Basic}) = Basic
# NOTE: need to annotate the output because otherwise it is type unstable!
Base.abs(x::Basic)::Basic = Basic(abs(SymEngine.BasicType(x)))
#Base.abs(x::BasicComplexNumber)::Basic = sqrt(real(x)^2 + imag(x)^2)
# abs(a) ^ real(b) * exp(-angle(a) * imag(b))
function Base.abs(x::BasicType{Val{:Pow}})
    a, b = get_args(x.x)
    abs(a)^real(b) * exp(-angle(a) * imag(b))
end

Base.angle(x::Basic)::Basic = Basic(angle(SymEngine.BasicType(x)))
#Base.angle(x::BasicComplexNumber)::Basic = atan(imag(x), real(x))
Base.angle(x::BasicType)::Basic = sangle(x.x)
Base.angle(::BasicType{Val{:Symbol}})::Basic = Basic(0)
Base.angle(::BasicType{Val{:Constant}})::Basic = Basic(0)

Base.conj(x::BiVarOp) = juliafunc(x)(conj.(get_args(x.x))...)
Base.conj(x::BasicTrigFunction) = juliafunc(x)(conj.(get_args(x.x)...)...)

Base.imag(::BasicType{Val{:Constant}}) = Basic(0)
Base.imag(::BasicType{Val{:Symbol}}) = Basic(0)
function Base.imag(x::BasicType{Val{:Add}})
    args = get_args(x.x)
    mapreduce(imag, +, args)
end
function Base.imag(x::BasicType{Val{:Mul}})
    args = (get_args(x.x)...,)
    get_mul_imag(args)
end
function Base.imag(x::BasicType{Val{:Pow}})
    a, b = get_args(x.x)
    if imag(a) == 0 && imag(b) == 0
        return Basic(0)
    else
        if imag(a) == 0
            return a^real(b) * sin(log(a) * imag(b))
        else
            return simag(x.x)
        end
    end
end
function Base.imag(x::BasicTrigFunction)
    a, = get_args(x.x)
    if imag(a) == 0
        return Basic(0)
    else
        return simag(x.x)
    end
end
function get_mul_imag(args::NTuple{N,Any}) where {N}
    imag(args[1]) * get_mul_real(args[2:end]) + real(args[1]) * get_mul_imag(args[2:end])
end
get_mul_imag(args::Tuple{Basic}) = imag(args[1])

function Base.real(x::BasicType{Val{:Add}})
    args = get_args(x.x)
    mapreduce(real, +, args)
end
function Base.real(x::BasicType{Val{:Pow}})
    a, b = get_args(x.x)
    if imag(a) == 0 && imag(b) == 0
        return x.x
    else
        if imag(a) == 0
            return a^real(b) * cos(log(a) * imag(b))
        else
            return sreal(x.x)
        end
    end
end
function Base.real(x::BasicType{Val{:Mul}})
    args = (get_args(x.x)...,)
    get_mul_real(args)
end
function Base.real(x::BasicTrigFunction)
    a, = get_args(x.x)
    if imag(a) == 0
        return x.x
    else
        return sreal(x.x)
    end
end
function get_mul_real(args::NTuple{N,Any}) where {N}
    real(args[1]) * get_mul_real(args[2:end]) - imag(args[1]) * get_mul_imag(args[2:end])
end
get_mul_real(args::Tuple{Basic}) = real(args[1])

@generated function juliafunc(x::BasicType{Val{T}}) where {T}
    SymEngine.map_fn(T, SymEngine.fn_map)
end

const SymReal = Union{Basic,SymEngine.BasicRealNumber}
YaoBlocks.RotationGate(block::GT, theta::T) where {D,T<:SymReal,GT<:AbstractBlock{D}} =
    RotationGate{D,T,GT}(block, theta)

YaoBlocks.phase(θ::SymReal) = PhaseGate(θ)
YaoBlocks.shift(θ::SymReal) = ShiftGate(θ)

YaoBlocks.mat(::Type{Basic}, gate::GT) where GT<:ConstantGate = _pretty_basic.(mat(gate))
YaoBlocks.mat(::Type{Basic}, gate::ConstGate.TGate) = Diagonal(Basic[1, exp(Basic(im)*Basic(π)/4)])
YaoBlocks.mat(::Type{Basic}, gate::ConstGate.TdagGate) = Diagonal(Basic[1, exp(-Basic(im)*Basic(π)/4)])
YaoArrayRegister._hadamard_matrix(::Type{Basic}) = 1 / sqrt(Basic(2)) * Basic[1 1; 1 -1]
YaoBlocks.mat(::Type{Basic}, ::HGate) = YaoArrayRegister._hadamard_matrix(Basic)
YaoBlocks.mat(::Type{Basic}, gate::ShiftGate) = Diagonal([1, exp(im * gate.theta)])
YaoBlocks.mat(::Type{Basic}, gate::PhaseGate) = exp(im * gate.theta) * IMatrix(2)
function YaoBlocks.mat(::Type{Basic}, R::RotationGate{D}) where {D}
    I = IMatrix(D^nqudits(R))
    return I * cos(R.theta / 2) - im * sin(R.theta / 2) * mat(Basic, R.block)
end
for GT in [:XGate, :YGate, :ZGate]
    @eval YaoBlocks.mat(::Type{Basic}, R::RotationGate{D,T,<:$GT}) where {D,T} =
        invoke(mat, Tuple{Type{Basic},RotationGate}, Basic, R)
end

for T in [:(RotationGate{D,<:SymReal} where D), :(PhaseGate{<:SymReal}), :(ShiftGate{<:SymReal})]
    @eval YaoBlocks.mat(gate::$T) = mat(Basic, gate)
end

YaoBlocks.PSwap(n::Int, locs::Tuple{Int,Int}, θ::SymReal) =
    YaoBlocks.PutBlock(n, rot(ConstGate.SWAPGate(), θ), locs)

YaoBlocks.pswap(n::Int, i::Int, j::Int, α::SymReal) = PSwap(n, (i, j), α)
YaoBlocks.pswap(i::Int, j::Int, α::SymReal) = n -> pswap(n, i, j, α)

SymEngine.subs(c::AbstractBlock, args...; kwargs...) = subs(Basic, c, args...; kwargs...)
function SymEngine.subs(::Type{T}, c::AbstractBlock, args...; kwargs...) where {T}
    c = setiparams(c, map(x -> T(subs(x, args...; kwargs...)), getiparams(c))...)
    chsubblocks(c, [subs(T, blk, args..., kwargs...) for blk in subblocks(c)])
end

# dumpload
YaoBlocks.tokenize_param(param::Basic) = QuoteNode(Symbol(param))
YaoBlocks.parse_param(x::QuoteNode) = :(Basic($x))
