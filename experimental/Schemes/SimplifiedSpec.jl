########################################################################
# Simplified Spectra                                                   #
########################################################################

### essential getters
underlying_scheme(X::SimplifiedSpec) = X.X
original(X::SimplifiedSpec) = X.Y
identification_maps(X::SimplifiedSpec) = (X.f, X.g)

### High-level constructors
@Markdown.doc """
    simplify(X::AbsSpec{<:Field})

Given an affine scheme ``X`` with coordinate ring ``R = 𝕜[x₁,…,xₙ]/I`` 
(or a localization thereof), use `Singular`'s `elimpart` to try 
to eliminate variables ``xᵢ`` to arrive at a simpler presentation 
``R ≅ R' = 𝕜[y₁,…,yₘ]/J`` for some ideal ``J``; return 
a `SimplifiedSpec` ``Y`` with ``X`` as its `original`.

***Note:*** The `ambient_coordinate_ring` of the output `Y` will be different
from the one of `X` and hence the two schemes will not compare using `==`.
"""
function simplify(X::AbsSpec{<:Field})
  L, f, g = simplify(OO(X))
  Y = Spec(L)
  YtoX = SpecMor(Y, X, f)
  XtoY = SpecMor(X, Y, g)
  set_attribute!(YtoX, :inverse, XtoY)
  set_attribute!(XtoY, :inverse, YtoX)
  return SimplifiedSpec(Y, X, YtoX, XtoY, check=false)
end

### Methods to roam in the ancestry tree
function some_ancestor(P::Function, X::SimplifiedSpec)
  return P(X) || some_ancestor(P, original(X))
end

function some_ancestor(P::Function, X::PrincipalOpenSubset)
  return P(X) || some_ancestor(P, ambient_scheme(X))
end

@Markdown.doc """
    some_ancestor(P::Function, X::AbsSpec)

Check whether property `P` holds for `X` or some ancestor of `X` in 
case it is a `PrincipalOpenSubset`, or a `SimplifiedSpec`.
"""
function some_ancestor(P::Function, X::AbsSpec)
  return P(X) # This case will only be called when we reached the root.
end

#=
# This crawls up the tree of charts until hitting one of the patches of C.
# Then it returns a pair (f, d) where f is the inclusion morphism 
# of U into the patch V of C and d is a Vector of elements of OO(V)
# which have to be inverted to arrive at U. That is: f induces an 
# isomorphism on the complement of d. 
=#
function _find_chart(U::AbsSpec, C::Covering;
    complement_equations::Vector{T}=elem_type(OO(U))[]
  ) where {T<:RingElem}
  any(W->(W === U), patches(C)) || error("patch not found")
  return identity_map(U), complement_equations
end

function _find_chart(U::PrincipalOpenSubset, C::Covering;
    complement_equations::Vector{T}=elem_type(OO(U))[]
  ) where {T<:RingElem}
  any(W->(W === U), patches(C)) && return identity_map(U), complement_equations
  V = ambient_scheme(U)
  ceq = push!(
              OO(V).(lifted_numerator.(complement_equations)),
              OO(V)(lifted_numerator(complement_equation(U)))
             )
  (f, d) = _find_chart(V, C, complement_equations=ceq)
  return compose(inclusion_morphism(U), f), d
end

function _find_chart(U::SimplifiedSpec, C::Covering;
    complement_equations::Vector{T}=elem_type(OO(U))[]
  ) where {T<:RingElem}
  any(W->(W === U), patches(C)) && return identity_map(U), complement_equations
  V = original(U)
  f, g = identification_maps(U)
  ceq = pullback(g).(complement_equations)
  h, d = _find_chart(V, C, complement_equations=ceq)
  return compose(f, h), d
end

#=
# This follows U in its ancestor tree up to the point 
# where a patch W in C is found. Then it recreates U as a 
# PrincipalOpenSubset UU of W and returns the identification 
# with UU.
=#
function _flatten_open_subscheme(
    U::PrincipalOpenSubset, C::Covering;
    iso::AbsSpecMor=begin
      UU = PrincipalOpenSubset(U, one(OO(U)))
      f = SpecMor(U, UU, hom(OO(UU), OO(U), gens(OO(U)), check=false), check=false)
      f_inv = SpecMor(UU, U, hom(OO(U), OO(UU), gens(OO(UU)), check=false), check=false)
      set_attribute!(f, :inverse, f_inv)
      set_attribute!(f_inv, :inverse, f)
      f
    end
  )
  some_ancestor(W->any(WW->(WW === W), patches(C)), U) || error("patch not found")
  W = ambient_scheme(U)
  V = domain(iso)
  UV = codomain(iso)
  hV = complement_equation(UV)
  hU = complement_equation(U)
  WV = PrincipalOpenSubset(W, OO(W).([lifted_numerator(hU), lifted_numerator(hV)]))
  ident = SpecMor(UV, WV, hom(OO(WV), OO(UV), gens(OO(UV)), check=false), check=false)
  new_iso =  compose(iso, ident)
  new_iso_inv = compose(inverse(ident), inverse(iso))
  set_attribute!(new_iso, :inverse, new_iso_inv)
  set_attribute!(new_iso_inv, :inverse, new_iso)
  if any(WW->(WW===W), patches(C)) 
    return new_iso
  end
  return _flatten_open_subscheme(W, C, iso=new_iso)
end

function _flatten_open_subscheme(
    U::SimplifiedSpec, C::Covering;
    iso::AbsSpecMor=begin 
      UU = PrincipalOpenSubset(U, one(OO(U)))
      f = SpecMor(U, UU, hom(OO(UU), OO(U), gens(OO(U)), check=false), check=false)
      f_inv = SpecMor(UU, U, hom(OO(U), OO(UU), gens(OO(UU)), check=false), check=false)
      set_attribute!(f, :inverse, f_inv)
      set_attribute!(f_inv, :inverse, f)
      f
    end
  )
  some_ancestor(W->any(WW->(WW === W), patches(C)), U) || error("patch not found")
  W = original(U)
  V = domain(iso)
  UV = codomain(iso)::PrincipalOpenSubset
  hV = complement_equation(UV)
  f, g = identification_maps(U)
  hVW = pullback(g)(hV)
  WV = PrincipalOpenSubset(W, hVW)
  ident = SpecMor(UV, WV, 
                  hom(OO(WV), OO(UV), 
                      OO(UV).(pullback(f).(gens(ambient_coordinate_ring(WV)))), 
                      check=false), 
                  check=false)
  new_iso =  compose(iso, ident)
  new_iso_inv = compose(inverse(ident), inverse(iso))
  set_attribute!(new_iso, :inverse, new_iso_inv)
  set_attribute!(new_iso_inv, :inverse, new_iso)
  if any(WW->(WW===W), patches(C)) 
    return new_iso
  end
  return _flatten_open_subscheme(W, C, iso=new_iso)
end

 
