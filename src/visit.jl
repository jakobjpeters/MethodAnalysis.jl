"""
    visit(operation)

Scan all loaded modules with `operation`. `operation(x)` should handle `x::Module`, `x::Function`,
`x::Method`, `x::MethodInstance`. Any return value from `operation` will be discarded.
"""
function visit(operation)
    visiting=Set{Module}()
    for mod in Base.loaded_modules_array()
        operation(mod)
        visit(operation, mod, visiting)
    end
    return nothing
end

function visit(operation, mod::Module, visiting=Set{Module}())
    push!(visiting, mod)
    println("Module ", mod)
    for nm in names(mod; all=true)
        if isdefined(mod, nm)
            obj = getfield(mod, nm)
            if isa(obj, Module)
                obj in visiting && continue
                visit(operation, obj, visiting)
            else
                visit(operation, obj)
            end
        end
    end
    return nothing
end

function visit(operation, f::Function)
    operation(f)
    Base.visit(methods(f).mt) do m
        visit(operation, m)
    end
    return nothing
end

function visit(operation, m::Method)
    operation(m)
    for fn in (:specializations,) # :invokes)   not sure if invokes contains additional methods
        if isdefined(m, fn)
            spec = getfield(m, fn)
            if spec === nothing
            elseif isa(spec, Core.TypeMapEntry) || isa(spec, Core.TypeMapLevel)
                Base.visit(spec) do mi
                    visit(operation, mi)
                end
            elseif isa(spec, Core.SimpleVector)
                visit(operation, spec)
            else
                error("unhandled type ", typeof(spec), ": ", spec)
            end
        end
    end
    return nothing
end

function visit(operation, sv::SimpleVector)
    for i = 1:length(sv)
        if isassigned(sv, i)
            visit(operation, sv[i])
        end
    end
    return nothing
end

function visit(operation, mi::MethodInstance)
    operation(mi)
    if isdefined(mi, :cache)
        visit(operation, mi.cache)
    end
    return nothing
end

# TODO: CodeInstance

visit(operation, x) = nothing

"""
    visit_backedges(operation, mi::MethodInstance)

Visit the backedges of `mi` and apply `operation`.
`operation(edge::MethodInstance)` should return `true` if the backedges of `edge` should in turn be visited,
`false` otherwise.
"""
visit_backedges(operation, mi::MethodInstance) =
    visit_backedges(operation, mi, Set{MethodInstance}())

function visit_backedges(operation, mi, visited)
    mi ∈ visited && return nothing
    push!(visited, mi)
    status = operation(mi)
    if status && isdefined(mi, :backedges)
        for edge in mi.backedges
            visit_backedges(operation, edge, visited)
        end
    end
    return nothing
end
