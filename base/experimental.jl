# This file is a part of Julia. License is MIT: https://julialang.org/license

"""
    Experimental

!!! warning
    Types, methods, or macros defined in this module are experimental and subject
    to change and will not have deprecations. Caveat emptor.
"""
module Experimental

using Base: Threads, sync_varname
using Base.Meta

"""
    Const(A::Array)

Mark an Array as constant/read-only. The invariant guaranteed is that you will not
modify an Array (through another reference) within an `@aliasscope` scope.

!!! warning
    Experimental API. Subject to change without deprecation.
"""
struct Const{T,N} <: DenseArray{T,N}
    a::Array{T,N}
end

Base.IndexStyle(::Type{<:Const}) = IndexLinear()
Base.size(C::Const) = size(C.a)
Base.axes(C::Const) = axes(C.a)
@eval Base.getindex(A::Const, i1::Int) =
    (Base.@inline; Core.const_arrayref($(Expr(:boundscheck)), A.a, i1))
@eval Base.getindex(A::Const, i1::Int, i2::Int, I::Int...) =
  (Base.@inline; Core.const_arrayref($(Expr(:boundscheck)), A.a, i1, i2, I...))

"""
    @aliasscope expr

Allows the compiler to assume that all `Const`s are not being modified through stores
within this scope, even if the compiler can't prove this to be the case.

!!! warning
    Experimental API. Subject to change without deprecation.
"""
macro aliasscope(body)
    sym = gensym()
    quote
        $(Expr(:aliasscope))
        $sym = $(esc(body))
        $(Expr(:popaliasscope))
        $sym
    end
end


function sync_end(c::Channel{Any})
    if !isready(c)
        # there must be at least one item to begin with
        close(c)
        return
    end
    nremaining::Int = 0
    while true
        event = take!(c)
        if event === :__completion__
            nremaining -= 1
            if nremaining == 0
                break
            end
        else
            nremaining += 1
            schedule(Task(()->begin
                try
                    wait(event)
                    put!(c, :__completion__)
                catch e
                    close(c, e)
                end
            end))
        end
    end
    close(c)
    nothing
end

"""
    Experimental.@sync

Wait until all lexically-enclosed uses of `@async`, `@spawn`, `@spawnat` and `@distributed`
are complete, or at least one of them has errored. The first exception is immediately
rethrown. It is the responsibility of the user to cancel any still-running operations
during error handling.

!!! Note
    This interface is experimental and subject to change or removal without notice.
"""
macro sync(block)
    var = esc(sync_varname)
    quote
        let $var = Channel(Inf)
            v = $(esc(block))
            sync_end($var)
            v
        end
    end
end

"""
    Experimental.@optlevel n::Int

Set the optimization level (equivalent to the `-O` command line argument)
for code in the current module. Submodules inherit the setting of their
parent module.

Supported values are 0, 1, 2, and 3.

The effective optimization level is the minimum of that specified on the
command line and in per-module settings. If a `--min-optlevel` value is
set on the command line, that is enforced as a lower bound.
"""
macro optlevel(n::Int)
    return Expr(:meta, :optlevel, n)
end

"""
    Experimental.@max_methods n::Int

Set the maximum number of potentially-matching methods considered when running inference
for methods defined in the current module. This setting affects inference of calls with
incomplete knowledge of the argument types.

Supported values are `1`, `2`, `3`, `4`, and `default` (currently equivalent to `3`).
"""
macro max_methods(n::Int)
    0 < n < 5 || error("We must have that `1 <= max_methods <= 4`, but `max_methods = $n`.")
    return Expr(:meta, :max_methods, n)
end

"""
    Experimental.@compiler_options optimize={0,1,2,3} compile={yes,no,all,min} infer={yes,no} max_methods={default,1,2,3,...}

Set compiler options for code in the enclosing module. Options correspond directly to
command-line options with the same name, where applicable. The following options
are currently supported:

  * `optimize`: Set optimization level.
  * `compile`: Toggle native code compilation. Currently only `min` is supported, which
    requests the minimum possible amount of compilation.
  * `infer`: Enable or disable type inference. If disabled, implies [`@nospecialize`](@ref).
  * `max_methods`: Maximum number of matching methods considered when running type inference.
"""
macro compiler_options(args...)
    opts = Expr(:block)
    for ex in args
        if isa(ex, Expr) && ex.head === :(=) && length(ex.args) == 2
            if ex.args[1] === :optimize
                push!(opts.args, Expr(:meta, :optlevel, ex.args[2]::Int))
            elseif ex.args[1] === :compile
                a = ex.args[2]
                a = #a === :no  ? 0 :
                    #a === :yes ? 1 :
                    #a === :all ? 2 :
                    a === :min ? 3 : error("invalid argument to \"compile\" option")
                push!(opts.args, Expr(:meta, :compile, a))
            elseif ex.args[1] === :infer
                a = ex.args[2]
                a = a === false || a === :no  ? 0 :
                    a === true  || a === :yes ? 1 : error("invalid argument to \"infer\" option")
                push!(opts.args, Expr(:meta, :infer, a))
            elseif ex.args[1] === :max_methods
                a = ex.args[2]
                a = a === :default ? 3 :
                  a isa Int ? ((0 < a < 5) ? a : error("We must have that `1 <= max_methods <= 4`, but `max_methods = $a`.")) :
                  error("invalid argument to \"max_methods\" option")
                push!(opts.args, Expr(:meta, :max_methods, a))
            else
                error("unknown option \"$(ex.args[1])\"")
            end
        else
            error("invalid option syntax")
        end
    end
    return opts
end

"""
    Experimental.@force_compile

Force compilation of the block or function (Julia's built-in interpreter is blocked from executing it).

# Examples

```
julia> occursin("interpreter", string(stacktrace(begin
           # with forced compilation
           Base.Experimental.@force_compile
           backtrace()
       end, true)))
false

julia> occursin("interpreter", string(stacktrace(begin
           # without forced compilation
           backtrace()
       end, true)))
true
```
"""
macro force_compile() Expr(:meta, :force_compile) end

# UI features for errors

"""
    Experimental.register_error_hint(handler, exceptiontype)

Register a "hinting" function `handler(io, exception)` that can
suggest potential ways for users to circumvent errors.  `handler`
should examine `exception` to see whether the conditions appropriate
for a hint are met, and if so generate output to `io`.
Packages should call `register_error_hint` from within their
`__init__` function.

For specific exception types, `handler` is required to accept additional arguments:

- `MethodError`: provide `handler(io, exc::MethodError, argtypes, kwargs)`,
  which splits the combined arguments into positional and keyword arguments.

When issuing a hint, the output should typically start with `\\n`.

If you define custom exception types, your `showerror` method can
support hints by calling [`Experimental.show_error_hints`](@ref).

# Example

```
julia> module Hinter

       only_int(x::Int)      = 1
       any_number(x::Number) = 2

       function __init__()
           Base.Experimental.register_error_hint(MethodError) do io, exc, argtypes, kwargs
               if exc.f == only_int
                    # Color is not necessary, this is just to show it's possible.
                    print(io, "\\nDid you mean to call ")
                    printstyled(io, "`any_number`?", color=:cyan)
               end
           end
       end

       end
```

Then if you call `Hinter.only_int` on something that isn't an `Int` (thereby triggering a `MethodError`), it issues the hint:

```
julia> Hinter.only_int(1.0)
ERROR: MethodError: no method matching only_int(::Float64)
Did you mean to call `any_number`?
Closest candidates are:
    ...
```

!!! compat "Julia 1.5"
    Custom error hints are available as of Julia 1.5.
!!! warning
    This interface is experimental and subject to change or removal without notice.
    To insulate yourself against changes, consider putting any registrations inside an
    `if isdefined(Base.Experimental, :register_error_hint) ... end` block.
"""
function register_error_hint(@nospecialize(handler), @nospecialize(exct::Type))
    list = get!(Vector{Any}, _hint_handlers, exct)
    push!(list, handler)
    return nothing
end

const _hint_handlers = IdDict{Type,Vector{Any}}()

"""
    Experimental.show_error_hints(io, ex, args...)

Invoke all handlers from [`Experimental.register_error_hint`](@ref) for the particular
exception type `typeof(ex)`. `args` must contain any other arguments expected by
the handler for that type.

!!! compat "Julia 1.5"
    Custom error hints are available as of Julia 1.5.
!!! warning
    This interface is experimental and subject to change or removal without notice.
"""
function show_error_hints(io, ex, args...)
    hinters = get!(()->[], _hint_handlers, typeof(ex))
    for handler in hinters
        try
            Base.invokelatest(handler, io, ex, args...)
        catch err
            tn = typeof(handler).name
            @error "Hint-handler $handler for $(typeof(ex)) in $(tn.module) caused an error"
        end
    end
end

# OpaqueClosure
include("opaque_closure.jl")

"""
    Experimental.@overlay mt [function def]

Define a method and add it to the method table `mt` instead of to the global method table.
This can be used to implement a method override mechanism. Regular compilation will not
consider these methods, and you should customize the compilation flow to look in these
method tables (e.g., using [`Core.Compiler.OverlayMethodTable`](@ref)).

"""
macro overlay(mt, def)
    def = macroexpand(__module__, def) # to expand @inline, @generated, etc
    if !isexpr(def, [:function, :(=)])
        error("@overlay requires a function Expr")
    end
    if isexpr(def.args[1], :call)
        def.args[1].args[1] = Expr(:overlay, mt, def.args[1].args[1])
    elseif isexpr(def.args[1], :where)
        def.args[1].args[1].args[1] = Expr(:overlay, mt, def.args[1].args[1].args[1])
    else
        error("@overlay requires a function Expr")
    end
    esc(def)
end

let new_mt(name::Symbol, mod::Module) = begin
        ccall(:jl_check_top_level_effect, Cvoid, (Any, Cstring), mod, "@MethodTable")
        ccall(:jl_new_method_table, Any, (Any, Any), name, mod)
    end
    @eval macro MethodTable(name::Symbol)
        esc(:(const $name = $$new_mt($(quot(name)), $(__module__))))
    end
end

"""
    Experimental.@MethodTable(name)

Create a new MethodTable in the current module, bound to `name`. This method table can be
used with the [`Experimental.@overlay`](@ref) macro to define methods for a function without
adding them to the global method table.
"""
:@MethodTable

end
