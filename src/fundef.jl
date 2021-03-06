# Temporary home for the code from https://github.com/MikeInnes/MacroTools.jl/pull/35
# until it either gets merged, or split off into a package.

using MacroTools
using MacroTools: @q

if VERSION >= v"0.6.0"
    include("utilsv6.jl")
else
    longdef1_where(ex) = ex
    function splitwhere(fdef)
        @assert(@capture(longdef1(fdef),
                         function (fcall_ | fcall_)
                         body_ end),
                "Not a function definition: $fdef")
        return fcall, body, nothing
    end

    """
        combinedef(dict::Dict)

    `combinedef` is the inverse of `splitdef`. It takes a splitdef-like dict
    and returns a function definition. """
    function combinedef(dict::Dict)
        rtype = get(dict, :rtype, :Any)
        params = get(dict, :params, [])
        :(function $(dict[:name]){$(params...)}($(dict[:args]...);
                                                $(dict[:kwargs]...))::$rtype
              $(dict[:body])
          end)
    end
end

function longdef1(ex)
  @match ex begin
    (f_(args__) = body_) => @q function $f($(args...)) $body end
    (f_(args__)::rtype_ = body_) => @q function $f($(args...))::$rtype $body end
    ((args__,) -> body_) => @q function ($(args...),) $body end
    (arg_ -> body_) => @q function ($arg,) $body end
    _ => longdef1_where(ex)
  end
end

doc"""    splitdef(fdef)

Match any function definition

```julia
function name{params}(args; kwargs)::rtype where {whereparams}
   body
end
```

and return `Dict(:name=>..., :args=>..., etc.)`. The definition can be rebuilt by
calling `MacroTools.combinedef(dict)`, or explicitly with the appropriate quoted
expression (good luck).
"""
function splitdef(fdef)
    error_msg = "Not a function definition: $fdef"
    fcall, body, whereparams = splitwhere(fdef)
    @assert(@capture(fcall, ((func_(args__; kwargs__)) |
                             (func_(args__; kwargs__)::rtype_) |
                             (func_(args__)) |
                             (func_(args__)::rtype_))),
            error_msg)
    @assert(@capture(func, (fname_{params__} | fname_)), error_msg)
    di = Dict(:name=>fname, :args=>args,
              :kwargs=>(kwargs===nothing ? [] : kwargs), :body=>body)
    if rtype !== nothing; di[:rtype] = rtype end
    if whereparams !== nothing; di[:whereparams] = whereparams end
    if params !== nothing; di[:params] = params end
    di
end


"""
    combinearg(arg_name, arg_type, is_splat, default)

`combinearg` is the inverse of `splitarg`. """
function combinearg(arg_name, arg_type, is_splat, default)
    a = arg_name===nothing ? :(::$arg_type) : :($arg_name::$arg_type)
    a2 = is_splat ? Expr(:..., a) : a
    return default === nothing ? a2 : Expr(:kw, a2, default)
end


macro splitcombine(fundef)
    dict = splitdef(fundef)
    esc(rebuilddef(striplines(dict)))
end


"""
    splitarg(arg)

Match function arguments (whether from a definition or a function call) such as
`x::Int=2` and return `(arg_name, arg_type, is_splat, default)`. `arg_name` and
`default` are `nothing` when they are absent. For example:

```julia
> map(splitarg, (:(f(a=2, x::Int=nothing, y, args...))).args[2:end])
4-element Array{Tuple{Symbol,Symbol,Bool,Any},1}:
 (:a, :Any, false, 2)        
 (:x, :Int, false, :nothing) 
 (:y, :Any, false, nothing)  
 (:args, :Any, true, nothing)
```
"""
function splitarg(arg_expr)
    splitvar(arg) =
        @match arg begin
            ::T_ => (nothing, T)
            name_::T_ => (name::Symbol, T)
            x_ => (x::Symbol, :Any)
        end
    (is_splat = @capture(arg_expr, arg_expr2_...)) || (arg_expr2 = arg_expr)
    if @capture(arg_expr2, arg_ = default_)
        @assert default !== nothing "splitarg cannot handle `nothing` as a default. Use a quoted `nothing` if possible. (MacroTools#35)"
        return (splitvar(arg)..., is_splat, default)
    else
        return (splitvar(arg_expr2)..., is_splat, nothing)
    end
end
