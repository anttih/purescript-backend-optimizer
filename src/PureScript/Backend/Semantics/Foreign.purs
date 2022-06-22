module PureScript.Backend.Semantics.Foreign where

import Prelude

import Data.Array as Array
import Data.Lazy as Lazy
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Tuple (Tuple(..))
import PureScript.Backend.Semantics (BackendSemantics(..), Env, ExternSpine(..), evalApp, evalMkFn, evalPrimOp)
import PureScript.Backend.Syntax (BackendAccessor(..), BackendOperator(..), BackendOperator1(..), BackendOperator2(..), BackendOperatorNum(..), BackendOperatorOrd(..))
import PureScript.CoreFn (Ident(..), Literal(..), ModuleName(..), Qualified(..))

type ForeignEval =
  Env -> Qualified Ident -> Array ExternSpine -> Maybe BackendSemantics

type ForeignSemantics =
  Tuple (Qualified Ident) ForeignEval

qualified :: String -> String -> Qualified Ident
qualified mod id = Qualified (Just (ModuleName mod)) (Ident id)

coreForeignSemantics :: Map (Qualified Ident) ForeignEval
coreForeignSemantics = Map.fromFoldable semantics
  where
  semantics =
    [ control_monad_st_internal_map
    , control_monad_st_internal_bind
    , control_monad_st_internal_pure
    , data_array_unsafeIndexImpl
    , data_eq_eqBooleanImpl
    , data_eq_eqCharImpl
    , data_eq_eqIntImpl
    , data_eq_eqNumberImpl
    , data_eq_eqStringImpl
    , data_euclideanRing_numDiv
    , data_heytingAlgebra_boolConj
    , data_heytingAlgebra_boolDisj
    , data_heytingAlgebra_boolImplies
    , data_heytingAlgebra_boolNot
    , data_ord_ordBoolean
    , data_ord_ordChar
    , data_ord_ordInt
    , data_ord_ordNumber
    , data_ord_ordString
    , data_ring_intSub
    , data_ring_numSub
    , data_semigroup_concatArray
    , data_semigroup_concatString
    , data_semiring_intAdd
    , data_semiring_intMul
    , data_semiring_numAdd
    , data_semiring_numMul
    , effect_bindE
    , effect_pureE
    , partial_unsafe_unsafePartial
    , unsafe_coerce_unsafeCoerce
    ]
      <> map data_function_uncurried_mkFn oneToTen
      <> map data_function_uncurried_runFn oneToTen
      <> map effect_uncurried_mkEffectFn oneToTen
      <> map effect_uncurried_runEffectFn oneToTen

  oneToTen =
    Array.range 1 10

effect_bindE :: ForeignSemantics
effect_bindE = Tuple (qualified "Effect" "bindE") effectBind

effect_pureE :: ForeignSemantics
effect_pureE = Tuple (qualified "Effect" "pureE") effectPure

control_monad_st_internal_bind :: ForeignSemantics
control_monad_st_internal_bind = Tuple (qualified "Control.Monad.ST.Internal" "bind_") effectBind

control_monad_st_internal_map :: ForeignSemantics
control_monad_st_internal_map = Tuple (qualified "Control.Monad.ST.Internal" "map_") effectMap

control_monad_st_internal_pure :: ForeignSemantics
control_monad_st_internal_pure = Tuple (qualified "Control.Monad.ST.Internal" "pure_") effectPure

data_array_unsafeIndexImpl :: ForeignSemantics
data_array_unsafeIndexImpl = Tuple (qualified "Data.Array" "unsafeIndexImpl") go
  where
  go _ _ = case _ of
    [ ExternApp [ a, b ] ] ->
      Just $ NeutPrimOp (Op2 OpArrayIndex a b)
    _ ->
      Nothing

data_eq_eqBooleanImpl :: ForeignSemantics
data_eq_eqBooleanImpl = Tuple (qualified "Data.Eq" "eqBooleanImpl") $ primBinaryOperator (OpBooleanOrd OpEq)

data_eq_eqIntImpl :: ForeignSemantics
data_eq_eqIntImpl = Tuple (qualified "Data.Eq" "eqIntImpl") $ primBinaryOperator (OpIntOrd OpEq)

data_eq_eqNumberImpl :: ForeignSemantics
data_eq_eqNumberImpl = Tuple (qualified "Data.Eq" "eqNumberImpl") $ primBinaryOperator (OpNumberOrd OpEq)

data_eq_eqCharImpl :: ForeignSemantics
data_eq_eqCharImpl = Tuple (qualified "Data.Eq" "eqCharImpl") $ primBinaryOperator (OpCharOrd OpEq)

data_eq_eqStringImpl :: ForeignSemantics
data_eq_eqStringImpl = Tuple (qualified "Data.Eq" "eqStringImpl") $ primBinaryOperator (OpStringOrd OpEq)

data_ord_ordBoolean :: ForeignSemantics
data_ord_ordBoolean = Tuple (qualified "Data.Ord" "ordBoolean") $ primOrdOperator OpBooleanOrd

data_ord_ordInt :: ForeignSemantics
data_ord_ordInt = Tuple (qualified "Data.Ord" "ordInt") $ primOrdOperator OpIntOrd

data_ord_ordNumber :: ForeignSemantics
data_ord_ordNumber = Tuple (qualified "Data.Ord" "ordNumber") $ primOrdOperator OpNumberOrd

data_ord_ordChar :: ForeignSemantics
data_ord_ordChar = Tuple (qualified "Data.Ord" "ordChar") $ primOrdOperator OpCharOrd

data_ord_ordString :: ForeignSemantics
data_ord_ordString = Tuple (qualified "Data.Ord" "ordString") $ primOrdOperator OpStringOrd

data_semiring_intAdd :: ForeignSemantics
data_semiring_intAdd = Tuple (qualified "Data.Semiring" "intAdd") $ primBinaryOperator (OpIntNum OpAdd)

data_semiring_intMul :: ForeignSemantics
data_semiring_intMul = Tuple (qualified "Data.Semiring" "intMul") $ primBinaryOperator (OpIntNum OpMultiply)

data_semiring_numAdd :: ForeignSemantics
data_semiring_numAdd = Tuple (qualified "Data.Semiring" "numAdd") $ primBinaryOperator (OpNumberNum OpAdd)

data_semiring_numMul :: ForeignSemantics
data_semiring_numMul = Tuple (qualified "Data.Semiring" "numMul") $ primBinaryOperator (OpNumberNum OpMultiply)

data_ring_intSub :: ForeignSemantics
data_ring_intSub = Tuple (qualified "Data.Ring" "intSub") $ primBinaryOperator (OpIntNum OpSubtract)

data_ring_numSub :: ForeignSemantics
data_ring_numSub = Tuple (qualified "Data.Ring" "numSub") $ primBinaryOperator (OpNumberNum OpSubtract)

data_euclideanRing_numDiv :: ForeignSemantics
data_euclideanRing_numDiv = Tuple (qualified "Data.EuclideanRing" "numDiv") $ primBinaryOperator (OpNumberNum OpDivide)

data_function_uncurried_mkFn :: Int -> ForeignSemantics
data_function_uncurried_mkFn n = Tuple (qualified "Data.Function.Uncurried" ("mkFn" <> show n)) go
  where
  go env _ = case _ of
    [ ExternApp [ sem ] ] ->
      Just $ SemMkFn (evalMkFn env n sem)
    _ ->
      Nothing

data_function_uncurried_runFn :: Int -> ForeignSemantics
data_function_uncurried_runFn n = Tuple (qualified "Data.Function.Uncurried" ("runFn" <> show n)) go
  where
  go _ _ = case _ of
    [ ExternApp items ]
      | Just { head, tail } <- Array.uncons items
      , Array.length tail == n ->
          Just $ NeutUncurriedApp head tail
    _ ->
      Nothing

effect_uncurried_mkEffectFn :: Int -> ForeignSemantics
effect_uncurried_mkEffectFn n = Tuple (qualified "Effect.Uncurried" ("mkEffectFn" <> show n)) go
  where
  go env _ = case _ of
    [ ExternApp [ sem ] ] ->
      Just $ SemMkEffectFn (evalMkFn env n sem)
    _ ->
      Nothing

effect_uncurried_runEffectFn :: Int -> ForeignSemantics
effect_uncurried_runEffectFn n = Tuple (qualified "Effect.Uncurried" ("runEffectFn" <> show n)) go
  where
  go _ _ = case _ of
    [ ExternApp items ]
      | Just { head, tail } <- Array.uncons items
      , Array.length tail == n ->
          Just $ NeutUncurriedEffectApp head tail
    _ ->
      Nothing

data_heytingAlgebra_boolConj :: ForeignSemantics
data_heytingAlgebra_boolConj = Tuple (qualified "Data.HeytingAlgebra" "boolConj") $ primBinaryOperator OpBooleanAnd

data_heytingAlgebra_boolDisj :: ForeignSemantics
data_heytingAlgebra_boolDisj = Tuple (qualified "Data.HeytingAlgebra" "boolDisj") $ primBinaryOperator OpBooleanOr

data_heytingAlgebra_boolNot :: ForeignSemantics
data_heytingAlgebra_boolNot = Tuple (qualified "Data.HeytingAlgebra" "boolNot") $ primUnaryOperator OpBooleanNot

data_heytingAlgebra_boolImplies :: ForeignSemantics
data_heytingAlgebra_boolImplies = Tuple (qualified "Data.HeytingAlgebra" "boolImplies") go
  where
  go _ _ = case _ of
    [ ExternApp [ a, b ] ]
      | NeutLit (LitBoolean false) <- a ->
          Just $ NeutLit (LitBoolean true)
      | NeutLit (LitBoolean true) <- b ->
          Just $ NeutLit (LitBoolean true)
      | NeutLit (LitBoolean x) <- a
      , NeutLit (LitBoolean y) <- b ->
          Just $ NeutLit (LitBoolean (not x || y))
    _ ->
      Nothing

unsafe_coerce_unsafeCoerce :: ForeignSemantics
unsafe_coerce_unsafeCoerce = Tuple (qualified "Unsafe.Coerce" "unsafeCoerce") go
  where
  go _ _ = case _ of
    [ ExternApp [ a ] ] ->
      Just a
    _ ->
      Nothing

primBinaryOperator :: BackendOperator2 -> ForeignEval
primBinaryOperator op env _ = case _ of
  [ ExternApp [ a, b ] ] ->
    Just $ evalPrimOp env (Op2 op a b)
  _ ->
    Nothing

primUnaryOperator :: BackendOperator1 -> ForeignEval
primUnaryOperator op env _ = case _ of
  [ ExternApp [ a ] ] ->
    Just $ evalPrimOp env (Op1 op a)
  _ ->
    Nothing

primOrdOperator :: (BackendOperatorOrd -> BackendOperator2) -> ForeignEval
primOrdOperator op env _ = case _ of
  [ ExternAccessor (GetProp "compare"), ExternApp [ a, b ], ExternPrimOp (OpIsTag tag) ]
    | isQualified "Data.Ordering" "LT" tag ->
        Just $ evalPrimOp env $ Op2 (op OpLt) a b
    | isQualified "Data.Ordering" "GT" tag ->
        Just $ evalPrimOp env $ Op2 (op OpGt) a b
    | isQualified "Data.Ordering" "EQ" tag ->
        Just $ evalPrimOp env $ Op2 (op OpEq) a b
  _ ->
    Nothing

effectBind :: ForeignEval
effectBind _ _ = case _ of
  [ ExternApp [ eff, SemLam ident next ] ] ->
    Just $ SemEffectBind ident eff next
  _ -> Nothing

effectMap :: ForeignEval
effectMap env _ = case _ of
  [ ExternApp [ fn, val ] ] ->
    Just $ SemEffectBind Nothing val \nextVal ->
      SemEffectPure (evalApp env fn [ nextVal ])
  _ -> Nothing

effectPure :: ForeignEval
effectPure _ _ = case _ of
  [ ExternApp [ val ] ] ->
    Just $ SemEffectPure val
  _ -> Nothing

isQualified :: String -> String -> Qualified Ident -> Boolean
isQualified mod tag = case _ of
  Qualified (Just (ModuleName mod')) (Ident tag') ->
    mod == mod' && tag == tag'
  _ ->
    false

assocBinaryOperatorL
  :: forall a
   . (BackendSemantics -> Maybe a)
  -> (Env -> a -> a -> BackendSemantics)
  -> (Env -> BackendSemantics -> BackendSemantics -> Maybe BackendSemantics)
  -> ForeignEval
assocBinaryOperatorL match op def env ident = case _ of
  [ ExternApp [ a, b ] ] ->
    case rewrite of
      Just _ ->
        rewrite
      Nothing ->
        def env a b
    where
    rewrite = case match a of
      Just lhs ->
        case match b of
          Just rhs ->
            Just $ op env lhs rhs
          Nothing ->
            case b of
              SemExtern ident' [ ExternApp [ x, y ] ] _ | ident == ident' ->
                case match x of
                  Just rhs -> do
                    let result = op env lhs rhs
                    Just $ externApp ident [ result, y ]
                  Nothing ->
                    case x of
                      SemExtern ident'' [ ExternApp [ v, w ] ] _ | ident == ident'' ->
                        case match v of
                          Just rhs -> do
                            let result = op env lhs rhs
                            Just $ externApp ident [ externApp ident [ result, w ], y ]
                          Nothing ->
                            Nothing
                      _ ->
                        Nothing
              _ ->
                Nothing
      Nothing ->
        case match b of
          Just rhs ->
            case a of
              SemExtern ident' [ ExternApp [ v, w ] ] _ | ident == ident' ->
                case match w of
                  Just lhs -> do
                    let result = op env lhs rhs
                    Just $ externApp ident [ v, result ]
                  Nothing ->
                    case w of
                      SemExtern ident'' [ ExternApp [ x, y ] ] _ | ident == ident'' ->
                        case match y of
                          Just lhs -> do
                            let result = op env lhs rhs
                            Just $ externApp ident [ externApp ident [ v, x ], result ]
                          Nothing ->
                            Nothing
                      _ ->
                        Nothing
              _ ->
                Nothing
          Nothing ->
            Nothing
  _ ->
    Nothing

data_semigroup_concatArray :: ForeignSemantics
data_semigroup_concatArray = Tuple (qualified "Data.Semigroup" "concatArray") $ assocBinaryOperatorL match op default
  where
  match = case _ of
    NeutLit (LitArray a) -> Just a
    _ -> Nothing

  op _ a b =
    NeutLit (LitArray (a <> b))

  default _ _ _ =
    Nothing

data_semigroup_concatString :: ForeignSemantics
data_semigroup_concatString = Tuple (qualified "Data.Semigroup" "concatString") $ primBinaryOperator OpStringAppend

externApp :: Qualified Ident -> Array BackendSemantics -> BackendSemantics
externApp ident spine = SemExtern ident [ ExternApp spine ] (Lazy.defer \_ -> NeutApp (NeutVar ident) spine)

partial_unsafe_unsafePartial :: ForeignSemantics
partial_unsafe_unsafePartial = Tuple (qualified "Partial.Unsafe" "_unsafePartial") go
  where
  go _ _ = case _ of
    [ ExternApp [ SemLam _ k ] ] ->
      Just $ k (NeutLit (LitRecord []))
    _ ->
      Nothing