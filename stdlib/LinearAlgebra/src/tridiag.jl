# This file is a part of Julia. License is MIT: https://julialang.org/license

#### Specialized matrix types ####

## (complex) symmetric tridiagonal matrices
struct SymTridiagonal{T, V<:AbstractVector{T}} <: AbstractMatrix{T}
    dv::V                        # diagonal
    ev::V                        # superdiagonal
    function SymTridiagonal{T, V}(dv, ev) where {T, V<:AbstractVector{T}}
        require_one_based_indexing(dv, ev)
        if !(length(dv) - 1 <= length(ev) <= length(dv))
            throw(DimensionMismatch("subdiagonal has wrong length. Has length $(length(ev)), but should be either $(length(dv) - 1) or $(length(dv))."))
        end
        new{T, V}(dv, ev)
    end
end

"""
    SymTridiagonal(dv::V, ev::V) where V <: AbstractVector

Construct a symmetric tridiagonal matrix from the diagonal (`dv`) and first
sub/super-diagonal (`ev`), respectively. The result is of type `SymTridiagonal`
and provides efficient specialized eigensolvers, but may be converted into a
regular matrix with [`convert(Array, _)`](@ref) (or `Array(_)` for short).

For `SymTridiagonal` block matrices, the elements of `dv` are symmetrized.
The argument `ev` is interpreted as the superdiagonal. Blocks from the
subdiagonal are (materialized) transpose of the corresponding superdiagonal blocks.

# Examples
```jldoctest
julia> dv = [1, 2, 3, 4]
4-element Vector{Int64}:
 1
 2
 3
 4

julia> ev = [7, 8, 9]
3-element Vector{Int64}:
 7
 8
 9

julia> SymTridiagonal(dv, ev)
4×4 SymTridiagonal{Int64, Vector{Int64}}:
 1  7  ⋅  ⋅
 7  2  8  ⋅
 ⋅  8  3  9
 ⋅  ⋅  9  4

julia> A = SymTridiagonal(fill([1 2; 3 4], 3), fill([1 2; 3 4], 2));

julia> A[1,1]
2×2 Symmetric{Int64, Matrix{Int64}}:
 1  2
 2  4

julia> A[1,2]
2×2 Matrix{Int64}:
 1  2
 3  4

julia> A[2,1]
2×2 Matrix{Int64}:
 1  3
 2  4
```
"""
SymTridiagonal(dv::V, ev::V) where {T,V<:AbstractVector{T}} = SymTridiagonal{T}(dv, ev)
SymTridiagonal{T}(dv::V, ev::V) where {T,V<:AbstractVector{T}} = SymTridiagonal{T,V}(dv, ev)
function SymTridiagonal{T}(dv::AbstractVector, ev::AbstractVector) where {T}
    SymTridiagonal(convert(AbstractVector{T}, dv)::AbstractVector{T},
                   convert(AbstractVector{T}, ev)::AbstractVector{T})
end

"""
    SymTridiagonal(A::AbstractMatrix)

Construct a symmetric tridiagonal matrix from the diagonal and first superdiagonal
of the symmetric matrix `A`.

# Examples
```jldoctest
julia> A = [1 2 3; 2 4 5; 3 5 6]
3×3 Matrix{Int64}:
 1  2  3
 2  4  5
 3  5  6

julia> SymTridiagonal(A)
3×3 SymTridiagonal{Int64, Vector{Int64}}:
 1  2  ⋅
 2  4  5
 ⋅  5  6

julia> B = reshape([[1 2; 2 3], [1 2; 3 4], [1 3; 2 4], [1 2; 2 3]], 2, 2);

julia> SymTridiagonal(B)
2×2 SymTridiagonal{Matrix{Int64}, Vector{Matrix{Int64}}}:
 [1 2; 2 3]  [1 3; 2 4]
 [1 2; 3 4]  [1 2; 2 3]
```
"""
function SymTridiagonal(A::AbstractMatrix)
    if (diag(A, 1) == transpose.(diag(A, -1))) && all(issymmetric.(diag(A, 0)))
        SymTridiagonal(diag(A, 0), diag(A, 1))
    else
        throw(ArgumentError("matrix is not symmetric; cannot convert to SymTridiagonal"))
    end
end

SymTridiagonal{T,V}(S::SymTridiagonal{T,V}) where {T,V<:AbstractVector{T}} = S
SymTridiagonal{T,V}(S::SymTridiagonal) where {T,V<:AbstractVector{T}} =
    SymTridiagonal(convert(V, S.dv)::V, convert(V, S.ev)::V)
SymTridiagonal{T}(S::SymTridiagonal{T}) where {T} = S
SymTridiagonal{T}(S::SymTridiagonal) where {T} =
    SymTridiagonal(convert(AbstractVector{T}, S.dv)::AbstractVector{T},
                   convert(AbstractVector{T}, S.ev)::AbstractVector{T})
SymTridiagonal(S::SymTridiagonal) = S

AbstractMatrix{T}(S::SymTridiagonal) where {T} =
    SymTridiagonal(convert(AbstractVector{T}, S.dv)::AbstractVector{T},
                   convert(AbstractVector{T}, S.ev)::AbstractVector{T})
function Matrix{T}(M::SymTridiagonal) where T
    n = size(M, 1)
    Mf = zeros(T, n, n)
    n == 0 && return Mf
    @inbounds for i = 1:n-1
        Mf[i,i] = symmetric(M.dv[i], :U)
        Mf[i+1,i] = transpose(M.ev[i])
        Mf[i,i+1] = M.ev[i]
    end
    Mf[n,n] = symmetric(M.dv[n], :U)
    return Mf
end
Matrix(M::SymTridiagonal{T}) where {T} = Matrix{T}(M)
Array(M::SymTridiagonal) = Matrix(M)

size(A::SymTridiagonal) = (length(A.dv), length(A.dv))
function size(A::SymTridiagonal, d::Integer)
    if d < 1
        throw(ArgumentError("dimension must be ≥ 1, got $d"))
    elseif d<=2
        return length(A.dv)
    else
        return 1
    end
end

similar(S::SymTridiagonal, ::Type{T}) where {T} = SymTridiagonal(similar(S.dv, T), similar(S.ev, T))
similar(S::SymTridiagonal, ::Type{T}, dims::Union{Dims{1},Dims{2}}) where {T} = zeros(T, dims...)

copyto!(dest::SymTridiagonal, src::SymTridiagonal) =
    (copyto!(dest.dv, src.dv); copyto!(dest.ev, _evview(src)); dest)

#Elementary operations
for func in (:conj, :copy, :real, :imag)
    @eval ($func)(M::SymTridiagonal) = SymTridiagonal(($func)(M.dv), ($func)(M.ev))
end

transpose(S::SymTridiagonal) = S
adjoint(S::SymTridiagonal{<:Real}) = S
adjoint(S::SymTridiagonal) = Adjoint(S)
Base.copy(S::Adjoint{<:Any,<:SymTridiagonal}) = SymTridiagonal(map(x -> copy.(adjoint.(x)), (S.parent.dv, S.parent.ev))...)

ishermitian(S::SymTridiagonal) = isreal(S.dv) && isreal(_evview(S))
issymmetric(S::SymTridiagonal) = true

function diag(M::SymTridiagonal{T}, n::Integer=0) where T<:Number
    # every branch call similar(..., ::Int) to make sure the
    # same vector type is returned independent of n
    absn = abs(n)
    if absn == 0
        return copyto!(similar(M.dv, length(M.dv)), M.dv)
    elseif absn == 1
        return copyto!(similar(M.ev, length(M.dv)-1), _evview(M))
    elseif absn <= size(M,1)
        return fill!(similar(M.dv, size(M,1)-absn), zero(T))
    else
        throw(ArgumentError(string("requested diagonal, $n, must be at least $(-size(M, 1)) ",
            "and at most $(size(M, 2)) for an $(size(M, 1))-by-$(size(M, 2)) matrix")))
    end
end
function diag(M::SymTridiagonal, n::Integer=0)
    # every branch call similar(..., ::Int) to make sure the
    # same vector type is returned independent of n
    if n == 0
        return copyto!(similar(M.dv, length(M.dv)), symmetric.(M.dv, :U))
    elseif n == 1
        return copyto!(similar(M.ev, length(M.dv)-1), _evview(M))
    elseif n == -1
        return copyto!(similar(M.ev, length(M.dv)-1), transpose.(_evview(M)))
    elseif n <= size(M,1)
        throw(ArgumentError("requested diagonal contains undefined zeros of an array type"))
    else
        throw(ArgumentError(string("requested diagonal, $n, must be at least $(-size(M, 1)) ",
            "and at most $(size(M, 2)) for an $(size(M, 1))-by-$(size(M, 2)) matrix")))
    end
end

+(A::SymTridiagonal, B::SymTridiagonal) = SymTridiagonal(A.dv+B.dv, _evview(A)+_evview(B))
-(A::SymTridiagonal, B::SymTridiagonal) = SymTridiagonal(A.dv-B.dv, _evview(A)-_evview(B))
-(A::SymTridiagonal) = SymTridiagonal(-A.dv, -A.ev)
*(A::SymTridiagonal, B::Number) = SymTridiagonal(A.dv*B, A.ev*B)
*(B::Number, A::SymTridiagonal) = SymTridiagonal(B*A.dv, B*A.ev)
/(A::SymTridiagonal, B::Number) = SymTridiagonal(A.dv/B, A.ev/B)
\(B::Number, A::SymTridiagonal) = SymTridiagonal(B\A.dv, B\A.ev)
==(A::SymTridiagonal, B::SymTridiagonal) = (A.dv==B.dv) && (_evview(A)==_evview(B))

@inline mul!(A::StridedVecOrMat, B::SymTridiagonal, C::StridedVecOrMat,
             alpha::Number, beta::Number) =
    _mul!(A, B, C, MulAddMul(alpha, beta))

@inline function _mul!(C::StridedVecOrMat, S::SymTridiagonal, B::StridedVecOrMat,
                          _add::MulAddMul)
    m, n = size(B, 1), size(B, 2)
    if !(m == size(S, 1) == size(C, 1))
        throw(DimensionMismatch("A has first dimension $(size(S,1)), B has $(size(B,1)), C has $(size(C,1)) but all must match"))
    end
    if n != size(C, 2)
        throw(DimensionMismatch("second dimension of B, $n, doesn't match second dimension of C, $(size(C,2))"))
    end

    if m == 0
        return C
    elseif iszero(_add.alpha)
        return _rmul_or_fill!(C, _add.beta)
    end

    α = S.dv
    β = S.ev
    @inbounds begin
        for j = 1:n
            x₊ = B[1, j]
            x₀ = zero(x₊)
            # If m == 1 then β[1] is out of bounds
            β₀ = m > 1 ? zero(β[1]) : zero(eltype(β))
            for i = 1:m - 1
                x₋, x₀, x₊ = x₀, x₊, B[i + 1, j]
                β₋, β₀ = β₀, β[i]
                _modify!(_add, β₋*x₋ + α[i]*x₀ + β₀*x₊, C, (i, j))
            end
            _modify!(_add, β₀*x₀ + α[m]*x₊, C, (m, j))
        end
    end

    return C
end

function dot(x::AbstractVector, S::SymTridiagonal, y::AbstractVector)
    require_one_based_indexing(x, y)
    nx, ny = length(x), length(y)
    (nx == size(S, 1) == ny) || throw(DimensionMismatch())
    if iszero(nx)
        return dot(zero(eltype(x)), zero(eltype(S)), zero(eltype(y)))
    end
    dv, ev = S.dv, S.ev
    x₀ = x[1]
    x₊ = x[2]
    sub = transpose(ev[1])
    r = dot(adjoint(dv[1])*x₀ + adjoint(sub)*x₊, y[1])
    @inbounds for j in 2:nx-1
        x₋, x₀, x₊ = x₀, x₊, x[j+1]
        sup, sub = transpose(sub), transpose(ev[j])
        r += dot(adjoint(sup)*x₋ + adjoint(dv[j])*x₀ + adjoint(sub)*x₊, y[j])
    end
    r += dot(adjoint(transpose(sub))*x₀ + adjoint(dv[nx])*x₊, y[nx])
    return r
end

(\)(T::SymTridiagonal, B::StridedVecOrMat) = ldlt(T)\B

# division with optional shift for use in shifted-Hessenberg solvers (hessenberg.jl):
ldiv!(A::SymTridiagonal, B::AbstractVecOrMat; shift::Number=false) = ldiv!(ldlt(A, shift=shift), B)
rdiv!(B::AbstractVecOrMat, A::SymTridiagonal; shift::Number=false) = rdiv!(B, ldlt(A, shift=shift))

eigen!(A::SymTridiagonal{<:BlasReal}) = Eigen(LAPACK.stegr!('V', A.dv, A.ev)...)
eigen(A::SymTridiagonal{T}) where T = eigen!(copy_oftype(A, eigtype(T)))

eigen!(A::SymTridiagonal{<:BlasReal}, irange::UnitRange) =
    Eigen(LAPACK.stegr!('V', 'I', A.dv, A.ev, 0.0, 0.0, irange.start, irange.stop)...)
eigen(A::SymTridiagonal{T}, irange::UnitRange) where T =
    eigen!(copy_oftype(A, eigtype(T)), irange)

eigen!(A::SymTridiagonal{<:BlasReal}, vl::Real, vu::Real) =
    Eigen(LAPACK.stegr!('V', 'V', A.dv, A.ev, vl, vu, 0, 0)...)
eigen(A::SymTridiagonal{T}, vl::Real, vu::Real) where T =
    eigen!(copy_oftype(A, eigtype(T)), vl, vu)

eigvals!(A::SymTridiagonal{<:BlasReal}) = LAPACK.stev!('N', A.dv, A.ev)[1]
eigvals(A::SymTridiagonal{T}) where T = eigvals!(copy_oftype(A, eigtype(T)))

eigvals!(A::SymTridiagonal{<:BlasReal}, irange::UnitRange) =
    LAPACK.stegr!('N', 'I', A.dv, A.ev, 0.0, 0.0, irange.start, irange.stop)[1]
eigvals(A::SymTridiagonal{T}, irange::UnitRange) where T =
    eigvals!(copy_oftype(A, eigtype(T)), irange)

eigvals!(A::SymTridiagonal{<:BlasReal}, vl::Real, vu::Real) =
    LAPACK.stegr!('N', 'V', A.dv, A.ev, vl, vu, 0, 0)[1]
eigvals(A::SymTridiagonal{T}, vl::Real, vu::Real) where T =
    eigvals!(copy_oftype(A, eigtype(T)), vl, vu)

#Computes largest and smallest eigenvalue
eigmax(A::SymTridiagonal) = eigvals(A, size(A, 1):size(A, 1))[1]
eigmin(A::SymTridiagonal) = eigvals(A, 1:1)[1]

#Compute selected eigenvectors only corresponding to particular eigenvalues
eigvecs(A::SymTridiagonal) = eigen(A).vectors

"""
    eigvecs(A::SymTridiagonal[, eigvals]) -> Matrix

Return a matrix `M` whose columns are the eigenvectors of `A`. (The `k`th eigenvector can
be obtained from the slice `M[:, k]`.)

If the optional vector of eigenvalues `eigvals` is specified, `eigvecs`
returns the specific corresponding eigenvectors.

# Examples
```jldoctest
julia> A = SymTridiagonal([1.; 2.; 1.], [2.; 3.])
3×3 SymTridiagonal{Float64, Vector{Float64}}:
 1.0  2.0   ⋅
 2.0  2.0  3.0
  ⋅   3.0  1.0

julia> eigvals(A)
3-element Vector{Float64}:
 -2.1400549446402604
  1.0000000000000002
  5.140054944640259

julia> eigvecs(A)
3×3 Matrix{Float64}:
  0.418304  -0.83205      0.364299
 -0.656749  -7.39009e-16  0.754109
  0.627457   0.5547       0.546448

julia> eigvecs(A, [1.])
3×1 Matrix{Float64}:
  0.8320502943378438
  4.263514128092366e-17
 -0.5547001962252291
```
"""
eigvecs(A::SymTridiagonal{<:BlasFloat}, eigvals::Vector{<:Real}) = LAPACK.stein!(A.dv, A.ev, eigvals)

function svdvals!(A::SymTridiagonal)
    vals = eigvals!(A)
    return sort!(map!(abs, vals, vals); rev=true)
end

# tril and triu

function istriu(M::SymTridiagonal, k::Integer=0)
    if k <= -1
        return true
    elseif k == 0
        return iszero(_evview(M))
    else # k >= 1
        return iszero(_evview(M)) && iszero(M.dv)
    end
end
istril(M::SymTridiagonal, k::Integer) = istriu(M, -k)
iszero(M::SymTridiagonal) =  iszero(_evview(M)) && iszero(M.dv)
isone(M::SymTridiagonal) =  iszero(_evview(M)) && all(isone, M.dv)
isdiag(M::SymTridiagonal) =  iszero(_evview(M))


function tril!(M::SymTridiagonal{T}, k::Integer=0) where T
    n = length(M.dv)
    if !(-n - 1 <= k <= n - 1)
        throw(ArgumentError(string("the requested diagonal, $k, must be at least ",
            "$(-n - 1) and at most $(n - 1) in an $n-by-$n matrix")))
    elseif k < -1
        fill!(M.ev, zero(T))
        fill!(M.dv, zero(T))
        return Tridiagonal(M.ev,M.dv,copy(M.ev))
    elseif k == -1
        fill!(M.dv, zero(T))
        return Tridiagonal(M.ev,M.dv,zero(M.ev))
    elseif k == 0
        return Tridiagonal(M.ev,M.dv,zero(M.ev))
    elseif k >= 1
        return Tridiagonal(M.ev,M.dv,copy(M.ev))
    end
end

function triu!(M::SymTridiagonal{T}, k::Integer=0) where T
    n = length(M.dv)
    if !(-n + 1 <= k <= n + 1)
        throw(ArgumentError(string("the requested diagonal, $k, must be at least ",
            "$(-n + 1) and at most $(n + 1) in an $n-by-$n matrix")))
    elseif k > 1
        fill!(M.ev, zero(T))
        fill!(M.dv, zero(T))
        return Tridiagonal(M.ev,M.dv,copy(M.ev))
    elseif k == 1
        fill!(M.dv, zero(T))
        return Tridiagonal(zero(M.ev),M.dv,M.ev)
    elseif k == 0
        return Tridiagonal(zero(M.ev),M.dv,M.ev)
    elseif k <= -1
        return Tridiagonal(M.ev,M.dv,copy(M.ev))
    end
end

###################
# Generic methods #
###################

## structured matrix methods ##
function Base.replace_in_print_matrix(A::SymTridiagonal, i::Integer, j::Integer, s::AbstractString)
    i==j-1||i==j||i==j+1 ? s : Base.replace_with_centered_mark(s)
end

# Implements the determinant using principal minors
# a, b, c are assumed to be the subdiagonal, diagonal, and superdiagonal of
# a tridiagonal matrix.
#Reference:
#    R. Usmani, "Inversion of a tridiagonal Jacobi matrix",
#    Linear Algebra and its Applications 212-213 (1994), pp.413-414
#    doi:10.1016/0024-3795(94)90414-6
function det_usmani(a::V, b::V, c::V, shift::Number=0) where {T,V<:AbstractVector{T}}
    require_one_based_indexing(a, b, c)
    n = length(b)
    θa = oneunit(T)+zero(shift)
    if n == 0
        return θa
    end
    θb = b[1]+shift
    for i in 2:n
        θb, θa = (b[i]+shift)*θb - a[i-1]*c[i-1]*θa, θb
    end
    return θb
end

# det with optional diagonal shift for use with shifted Hessenberg factorizations
det(A::SymTridiagonal; shift::Number=false) = det_usmani(A.ev, A.dv, A.ev, shift)
logabsdet(A::SymTridiagonal; shift::Number=false) = logabsdet(ldlt(A; shift=shift))

@inline function getindex(A::SymTridiagonal{T}, i::Integer, j::Integer) where T
    @boundscheck checkbounds(A, i, j)
    if i == j
        return symmetric((@inbounds A.dv[i]), :U)::symmetric_type(eltype(A.dv))
    elseif i == j + 1
        return copy(transpose(@inbounds A.ev[j])) # materialized for type stability
    elseif i + 1 == j
        return @inbounds A.ev[i]
    else
        return zero(T)
    end
end

@inline function setindex!(A::SymTridiagonal, x, i::Integer, j::Integer)
    @boundscheck checkbounds(A, i, j)
    if i == j
        @inbounds A.dv[i] = x
    else
        throw(ArgumentError("cannot set off-diagonal entry ($i, $j)"))
    end
    return x
end

## Tridiagonal matrices ##
struct Tridiagonal{T,V<:AbstractVector{T}} <: AbstractMatrix{T}
    dl::V    # sub-diagonal
    d::V     # diagonal
    du::V    # sup-diagonal
    du2::V   # supsup-diagonal for pivoting in LU
    function Tridiagonal{T,V}(dl, d, du) where {T,V<:AbstractVector{T}}
        require_one_based_indexing(dl, d, du)
        n = length(d)
        if (length(dl) != n-1 || length(du) != n-1) && !(length(d) == 0 && length(dl) == 0 && length(du) == 0)
            throw(ArgumentError(string("cannot construct Tridiagonal from incompatible ",
                "lengths of subdiagonal, diagonal and superdiagonal: ",
                "($(length(dl)), $(length(d)), $(length(du)))")))
        end
        new{T,V}(dl, d, du)
    end
    # constructor used in lu!
    function Tridiagonal{T,V}(dl, d, du, du2) where {T,V<:AbstractVector{T}}
        require_one_based_indexing(dl, d, du, du2)
        # length checks?
        new{T,V}(dl, d, du, du2)
    end
end

"""
    Tridiagonal(dl::V, d::V, du::V) where V <: AbstractVector

Construct a tridiagonal matrix from the first subdiagonal, diagonal, and first superdiagonal,
respectively. The result is of type `Tridiagonal` and provides efficient specialized linear
solvers, but may be converted into a regular matrix with
[`convert(Array, _)`](@ref) (or `Array(_)` for short).
The lengths of `dl` and `du` must be one less than the length of `d`.

# Examples
```jldoctest
julia> dl = [1, 2, 3];

julia> du = [4, 5, 6];

julia> d = [7, 8, 9, 0];

julia> Tridiagonal(dl, d, du)
4×4 Tridiagonal{Int64, Vector{Int64}}:
 7  4  ⋅  ⋅
 1  8  5  ⋅
 ⋅  2  9  6
 ⋅  ⋅  3  0
```
"""
Tridiagonal(dl::V, d::V, du::V) where {T,V<:AbstractVector{T}} = Tridiagonal{T,V}(dl, d, du)
Tridiagonal(dl::V, d::V, du::V, du2::V) where {T,V<:AbstractVector{T}} = Tridiagonal{T,V}(dl, d, du, du2)
function Tridiagonal{T}(dl::AbstractVector, d::AbstractVector, du::AbstractVector) where {T}
    Tridiagonal(map(x->convert(AbstractVector{T}, x), (dl, d, du))...)
end

"""
    Tridiagonal(A)

Construct a tridiagonal matrix from the first sub-diagonal,
diagonal and first super-diagonal of the matrix `A`.

# Examples
```jldoctest
julia> A = [1 2 3 4; 1 2 3 4; 1 2 3 4; 1 2 3 4]
4×4 Matrix{Int64}:
 1  2  3  4
 1  2  3  4
 1  2  3  4
 1  2  3  4

julia> Tridiagonal(A)
4×4 Tridiagonal{Int64, Vector{Int64}}:
 1  2  ⋅  ⋅
 1  2  3  ⋅
 ⋅  2  3  4
 ⋅  ⋅  3  4
```
"""
Tridiagonal(A::AbstractMatrix) = Tridiagonal(diag(A,-1), diag(A,0), diag(A,1))

Tridiagonal(A::Tridiagonal) = A
Tridiagonal{T}(A::Tridiagonal{T}) where {T} = A
function Tridiagonal{T}(A::Tridiagonal) where {T}
    dl, d, du = map(x->convert(AbstractVector{T}, x)::AbstractVector{T},
                    (A.dl, A.d, A.du))
    if isdefined(A, :du2)
        Tridiagonal(dl, d, du, convert(AbstractVector{T}, A.du2)::AbstractVector{T})
    else
        Tridiagonal(dl, d, du)
    end
end

size(M::Tridiagonal) = (length(M.d), length(M.d))
function size(M::Tridiagonal, d::Integer)
    if d < 1
        throw(ArgumentError("dimension d must be ≥ 1, got $d"))
    elseif d <= 2
        return length(M.d)
    else
        return 1
    end
end

function Matrix{T}(M::Tridiagonal{T}) where T
    A = zeros(T, size(M))
    for i = 1:length(M.d)
        A[i,i] = M.d[i]
    end
    for i = 1:length(M.d)-1
        A[i+1,i] = M.dl[i]
        A[i,i+1] = M.du[i]
    end
    A
end
Matrix(M::Tridiagonal{T}) where {T} = Matrix{T}(M)
Array(M::Tridiagonal) = Matrix(M)

similar(M::Tridiagonal, ::Type{T}) where {T} = Tridiagonal(similar(M.dl, T), similar(M.d, T), similar(M.du, T))
similar(M::Tridiagonal, ::Type{T}, dims::Union{Dims{1},Dims{2}}) where {T} = zeros(T, dims...)

# Operations on Tridiagonal matrices
copyto!(dest::Tridiagonal, src::Tridiagonal) = (copyto!(dest.dl, src.dl); copyto!(dest.d, src.d); copyto!(dest.du, src.du); dest)

#Elementary operations
for func in (:conj, :copy, :real, :imag)
    @eval function ($func)(M::Tridiagonal)
        Tridiagonal(($func)(M.dl), ($func)(M.d), ($func)(M.du))
    end
end

adjoint(S::Tridiagonal) = Adjoint(S)
transpose(S::Tridiagonal) = Transpose(S)
adjoint(S::Tridiagonal{<:Real}) = Tridiagonal(S.du, S.d, S.dl)
transpose(S::Tridiagonal{<:Number}) = Tridiagonal(S.du, S.d, S.dl)
Base.copy(aS::Adjoint{<:Any,<:Tridiagonal}) = (S = aS.parent; Tridiagonal(map(x -> copy.(adjoint.(x)), (S.du, S.d, S.dl))...))
Base.copy(tS::Transpose{<:Any,<:Tridiagonal}) = (S = tS.parent; Tridiagonal(map(x -> copy.(transpose.(x)), (S.du, S.d, S.dl))...))

ishermitian(S::Tridiagonal) = all(ishermitian, S.d) && all(Iterators.map((x, y) -> x == y', S.du, S.dl))
issymmetric(S::Tridiagonal) = all(issymmetric, S.d) && all(Iterators.map((x, y) -> x == transpose(y), S.du, S.dl))

\(A::Adjoint{<:Any,<:Tridiagonal}, B::Adjoint{<:Any,<:StridedVecOrMat}) = copy(A) \ B

function diag(M::Tridiagonal{T}, n::Integer=0) where T
    # every branch call similar(..., ::Int) to make sure the
    # same vector type is returned independent of n
    if n == 0
        return copyto!(similar(M.d, length(M.d)), M.d)
    elseif n == -1
        return copyto!(similar(M.dl, length(M.dl)), M.dl)
    elseif n == 1
        return copyto!(similar(M.du, length(M.du)), M.du)
    elseif abs(n) <= size(M,1)
        return fill!(similar(M.d, size(M,1)-abs(n)), zero(T))
    else
        throw(ArgumentError(string("requested diagonal, $n, must be at least $(-size(M, 1)) ",
            "and at most $(size(M, 2)) for an $(size(M, 1))-by-$(size(M, 2)) matrix")))
    end
end

@inline function getindex(A::Tridiagonal{T}, i::Integer, j::Integer) where T
    @boundscheck checkbounds(A, i, j)
    if i == j
        return @inbounds A.d[i]
    elseif i == j + 1
        return @inbounds A.dl[j]
    elseif i + 1 == j
        return @inbounds A.du[i]
    else
        return zero(T)
    end
end

@inline function setindex!(A::Tridiagonal, x, i::Integer, j::Integer)
    @boundscheck checkbounds(A, i, j)
    if i == j
        @inbounds A.d[i] = x
    elseif i - j == 1
        @inbounds A.dl[j] = x
    elseif j - i == 1
        @inbounds A.du[i] = x
    elseif !iszero(x)
        throw(ArgumentError(string("cannot set entry ($i, $j) off ",
            "the tridiagonal band to a nonzero value ($x)")))
    end
    return x
end

## structured matrix methods ##
function Base.replace_in_print_matrix(A::Tridiagonal,i::Integer,j::Integer,s::AbstractString)
    i==j-1||i==j||i==j+1 ? s : Base.replace_with_centered_mark(s)
end


#tril and triu

iszero(M::Tridiagonal) = iszero(M.dl) && iszero(M.d) && iszero(M.du)
isone(M::Tridiagonal) = iszero(M.dl) && all(isone, M.d) && iszero(M.du)
function istriu(M::Tridiagonal, k::Integer=0)
    if k <= -1
        return true
    elseif k == 0
        return iszero(M.dl)
    elseif k == 1
        return iszero(M.dl) && iszero(M.d)
    else # k >= 2
        return iszero(M.dl) && iszero(M.d) && iszero(M.du)
    end
end
function istril(M::Tridiagonal, k::Integer=0)
    if k >= 1
        return true
    elseif k == 0
        return iszero(M.du)
    elseif k == -1
        return iszero(M.du) && iszero(M.d)
    else # k <= -2
        return iszero(M.du) && iszero(M.d) && iszero(M.dl)
    end
end
isdiag(M::Tridiagonal) = iszero(M.dl) && iszero(M.du)

function tril!(M::Tridiagonal{T}, k::Integer=0) where T
    n = length(M.d)
    if !(-n - 1 <= k <= n - 1)
        throw(ArgumentError(string("the requested diagonal, $k, must be at least ",
            "$(-n - 1) and at most $(n - 1) in an $n-by-$n matrix")))
    elseif k < -1
        fill!(M.dl, zero(T))
        fill!(M.d, zero(T))
        fill!(M.du, zero(T))
    elseif k == -1
        fill!(M.d, zero(T))
        fill!(M.du, zero(T))
    elseif k == 0
        fill!(M.du, zero(T))
    end
    return M
end

function triu!(M::Tridiagonal{T}, k::Integer=0) where T
    n = length(M.d)
    if !(-n + 1 <= k <= n + 1)
        throw(ArgumentError(string("the requested diagonal, $k, must be at least ",
            "$(-n + 1) and at most $(n + 1) in an $n-by-$n matrix")))
    elseif k > 1
        fill!(M.dl, zero(T))
        fill!(M.d, zero(T))
        fill!(M.du, zero(T))
    elseif k == 1
        fill!(M.dl, zero(T))
        fill!(M.d, zero(T))
    elseif k == 0
        fill!(M.dl, zero(T))
    end
    return M
end

###################
# Generic methods #
###################

+(A::Tridiagonal, B::Tridiagonal) = Tridiagonal(A.dl+B.dl, A.d+B.d, A.du+B.du)
-(A::Tridiagonal, B::Tridiagonal) = Tridiagonal(A.dl-B.dl, A.d-B.d, A.du-B.du)
*(A::Tridiagonal, B::Number) = Tridiagonal(A.dl*B, A.d*B, A.du*B)
*(B::Number, A::Tridiagonal) = Tridiagonal(B*A.dl, B*A.d, B*A.du)
/(A::Tridiagonal, B::Number) = Tridiagonal(A.dl/B, A.d/B, A.du/B)
\(B::Number, A::Tridiagonal) = Tridiagonal(B\A.dl, B\A.d, B\A.du)

==(A::Tridiagonal, B::Tridiagonal) = (A.dl==B.dl) && (A.d==B.d) && (A.du==B.du)
function ==(A::Tridiagonal, B::SymTridiagonal)
    iseq = all(Iterators.map((x, y) -> x == transpose(y), A.du, A.dl))
    iseq = iseq && A.du == _evview(B)
    iseq && all(Iterators.map((x, y) -> x == symmetric(y, :U), A.d, B.dv))
end
==(A::SymTridiagonal, B::Tridiagonal) = B == A

det(A::Tridiagonal) = det_usmani(A.dl, A.d, A.du)

AbstractMatrix{T}(M::Tridiagonal) where {T} = Tridiagonal{T}(M)
Tridiagonal{T}(M::SymTridiagonal{T}) where {T} = Tridiagonal(M)
function SymTridiagonal{T}(M::Tridiagonal) where T
    if issymmetric(M)
        return SymTridiagonal{T}(convert(AbstractVector{T},M.d), convert(AbstractVector{T},M.dl))
    else
        throw(ArgumentError("Tridiagonal is not symmetric, cannot convert to SymTridiagonal"))
    end
end

Base._sum(A::Tridiagonal, ::Colon) = sum(A.d) + sum(A.dl) + sum(A.du)
function Base._sum(A::SymTridiagonal, ::Colon)
    se = sum(_evview(A))
    symmetric(sum(A.dv), :U) + se + transpose(se)
end

function Base._sum(A::Tridiagonal, dims::Integer)
    res = Base.reducedim_initarray(A, dims, zero(eltype(A)))
    n = length(A.d)
    if n == 0
        return res
    elseif n == 1
        res[1] = A.d[1]
        return res
    end
    @inbounds begin
        if dims == 1
            res[1] = A.dl[1] + A.d[1]
            for i = 2:n-1
                res[i] = A.dl[i] + A.d[i] + A.du[i-1]
            end
            res[n] = A.d[n] + A.du[n-1]
        elseif dims == 2
            res[1] = A.d[1] + A.du[1]
            for i = 2:n-1
                res[i] = A.dl[i-1] + A.d[i] + A.du[i]
            end
            res[n] = A.dl[n-1] + A.d[n]
        elseif dims >= 3
            for i = 1:n-1
                res[i,i+1] = A.du[i]
                res[i,i]   = A.d[i]
                res[i+1,i] = A.dl[i]
            end
            res[n,n] = A.d[n]
        end
    end
    res
end

function Base._sum(A::SymTridiagonal, dims::Integer)
    res = Base.reducedim_initarray(A, dims, zero(eltype(A)))
    n = length(A.dv)
    if n == 0
        return res
    elseif n == 1
        res[1] = A.dv[1]
        return res
    end
    @inbounds begin
        if dims == 1
            res[1] = transpose(A.ev[1]) + symmetric(A.dv[1], :U)
            for i = 2:n-1
                res[i] = transpose(A.ev[i]) + symmetric(A.dv[i], :U) + A.ev[i-1]
            end
            res[n] = symmetric(A.dv[n], :U) + A.ev[n-1]
        elseif dims == 2
            res[1] = symmetric(A.dv[1], :U) + A.ev[1]
            for i = 2:n-1
                res[i] = transpose(A.ev[i-1]) + symmetric(A.dv[i], :U) + A.ev[i]
            end
            res[n] = transpose(A.ev[n-1]) + symmetric(A.dv[n], :U)
        elseif dims >= 3
            for i = 1:n-1
                res[i,i+1] = A.ev[i]
                res[i,i]   = symmetric(A.dv[i], :U)
                res[i+1,i] = transpose(A.ev[i])
            end
            res[n,n] = symmetric(A.dv[n], :U)
        end
    end
    res
end

function dot(x::AbstractVector, A::Tridiagonal, y::AbstractVector)
    require_one_based_indexing(x, y)
    nx, ny = length(x), length(y)
    (nx == size(A, 1) == ny) || throw(DimensionMismatch())
    if iszero(nx)
        return dot(zero(eltype(x)), zero(eltype(A)), zero(eltype(y)))
    end
    x₀ = x[1]
    x₊ = x[2]
    dl, d, du = A.dl, A.d, A.du
    r = dot(adjoint(d[1])*x₀ + adjoint(dl[1])*x₊, y[1])
    @inbounds for j in 2:nx-1
        x₋, x₀, x₊ = x₀, x₊, x[j+1]
        r += dot(adjoint(du[j-1])*x₋ + adjoint(d[j])*x₀ + adjoint(dl[j])*x₊, y[j])
    end
    r += dot(adjoint(du[nx-1])*x₀ + adjoint(d[nx])*x₊, y[nx])
    return r
end
