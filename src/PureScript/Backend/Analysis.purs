module PureScript.Backend.Analysis where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmptyArray
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype, over)
import Data.Set (Set)
import Data.Set as Set
import Data.Traversable (foldMap, foldr)
import Data.Tuple (Tuple(..), snd)
import PureScript.Backend.Syntax (class HasSyntax, BackendSyntax(..), Level, syntaxOf)
import PureScript.CoreFn (Ident, ModuleName, Qualified(..))

newtype Usage = Usage
  { count :: Int
  , captured :: Boolean
  , arities :: Set Int
  }

derive instance Newtype Usage _

instance Semigroup Usage where
  append (Usage a) (Usage b) = Usage
    { count: a.count + b.count
    , captured: a.captured || b.captured
    , arities: Set.union a.arities b.arities
    }

instance Monoid Usage where
  mempty = Usage { count: 0, captured: false, arities: Set.empty }

data Complexity = Trivial | TopLevelDeref | Deref | NonTrivial

derive instance Eq Complexity
derive instance Ord Complexity

instance Semigroup Complexity where
  append = case _, _ of
    Trivial, a -> a
    b, Trivial -> b
    TopLevelDeref, a -> a
    b, TopLevelDeref -> b
    Deref, a -> a
    b, Deref -> b
    _, _ -> NonTrivial

instance Monoid Complexity where
  mempty = Trivial

newtype BackendAnalysis = BackendAnalysis
  { usages :: Map Level Usage
  , size :: Int
  , complexity :: Complexity
  , args :: Array Usage
  , rewrite :: Boolean
  , deps :: Set ModuleName
  }

derive instance Newtype BackendAnalysis _

instance Semigroup BackendAnalysis where
  append (BackendAnalysis a) (BackendAnalysis b) = BackendAnalysis
    { usages: Map.unionWith append a.usages b.usages
    , size: a.size + b.size
    , complexity: a.complexity <> b.complexity
    , args: []
    , rewrite: a.rewrite || b.rewrite
    , deps: Set.union a.deps b.deps
    }

instance Monoid BackendAnalysis where
  mempty = BackendAnalysis
    { usages: Map.empty
    , size: 0
    , complexity: Trivial
    , args: []
    , rewrite: false
    , deps: Set.empty
    }

bound :: Level -> BackendAnalysis -> BackendAnalysis
bound level (BackendAnalysis s) = BackendAnalysis s { usages = Map.delete level s.usages }

boundArg :: Level -> BackendAnalysis -> BackendAnalysis
boundArg level (BackendAnalysis s) = case Map.pop level s.usages of
  Nothing ->
    BackendAnalysis s { args = Array.cons mempty s.args }
  Just (Tuple u us) ->
    BackendAnalysis s { usages = us, args = Array.cons u s.args }

withArgs :: Array Usage -> BackendAnalysis -> BackendAnalysis
withArgs args (BackendAnalysis s) = BackendAnalysis s { args = args }

withRewrite :: BackendAnalysis -> BackendAnalysis
withRewrite (BackendAnalysis s) = BackendAnalysis s { rewrite = true }

used :: Level -> BackendAnalysis
used level = do
  let BackendAnalysis s = mempty
  BackendAnalysis s
    { usages = Map.singleton level (Usage { count: 1, captured: false, arities: Set.empty })
    }

usedDep :: ModuleName -> BackendAnalysis
usedDep mn = do
  let BackendAnalysis s = mempty
  BackendAnalysis s { deps = Set.singleton mn }

bump :: BackendAnalysis -> BackendAnalysis
bump (BackendAnalysis s) = BackendAnalysis s { size = s.size + 1 }

complex :: Complexity -> BackendAnalysis -> BackendAnalysis
complex complexity (BackendAnalysis s) = BackendAnalysis s { complexity = complexity }

capture :: BackendAnalysis -> BackendAnalysis
capture (BackendAnalysis s) = BackendAnalysis s { usages = over Usage _ { captured = true } <$> s.usages }

callArity :: Level -> Int -> BackendAnalysis -> BackendAnalysis
callArity lvl arity (BackendAnalysis s) = BackendAnalysis s
  { usages = Map.update (Just <<< over Usage (\us -> us { arities = Set.insert arity us.arities })) lvl s.usages
  }

class HasAnalysis a where
  analysisOf :: a -> BackendAnalysis

analyze :: forall a. HasAnalysis a => HasSyntax a => (Qualified Ident -> BackendAnalysis) -> BackendSyntax a -> BackendAnalysis
analyze externAnalysis expr = case expr of
  Var qi@(Qualified mn _) -> do
    let BackendAnalysis { args } = externAnalysis qi
    withArgs args $ bump $ foldMap usedDep mn
  Local _ lvl ->
    bump (used lvl)
  Let _ lvl a b ->
    bump (complex NonTrivial (analysisOf a <> bound lvl (analysisOf b)))
  LetRec lvl as b ->
    bump (complex NonTrivial (bound lvl (foldMap (analysisOf <<< snd) as <> analysisOf b)))
  EffectBind _ lvl a b ->
    bump (complex NonTrivial (analysisOf a <> bound lvl (analysisOf b)))
  EffectPure a ->
    bump (analysisOf a)
  Abs args _ ->
    complex NonTrivial $ capture $ foldr (boundArg <<< snd) (analyzeDefault expr) args
  UncurriedAbs args _ ->
    complex NonTrivial $ capture $ foldr (boundArg <<< snd) (analyzeDefault expr) args
  UncurriedApp hd tl | BackendAnalysis { args } <- analysisOf hd ->
    withArgs (Array.drop (Array.length tl) args) case syntaxOf hd of
      Just (Local _ lvl) ->
        callArity lvl (Array.length tl) analysis
      _ ->
        analysis
    where
    analysis = complex NonTrivial $ analyzeDefault expr
  UncurriedEffectAbs args _ ->
    complex NonTrivial $ capture $ foldr (boundArg <<< snd) (analyzeDefault expr) args
  UncurriedEffectApp hd tl | BackendAnalysis { args } <- analysisOf hd ->
    withArgs (Array.drop (Array.length tl) args) case syntaxOf hd of
      Just (Local _ lvl) ->
        callArity lvl (Array.length tl) analysis
      _ ->
        analysis
    where
    analysis = complex NonTrivial $ analyzeDefault expr
  App hd tl | BackendAnalysis { args } <- analysisOf hd ->
    withArgs (Array.drop (NonEmptyArray.length tl) args) case syntaxOf hd of
      Just (Local _ lvl) ->
        callArity lvl (NonEmptyArray.length tl) analysis
      _ ->
        analysis
    where
    analysis = complex NonTrivial $ analyzeDefault expr
  Update _ _ ->
    complex NonTrivial $ analyzeDefault expr
  CtorSaturated (Qualified mn _) _ _ _ cs ->
    bump (foldMap (foldMap analysisOf) cs <> foldMap usedDep mn)
  CtorDef _ _ _ _ ->
    complex NonTrivial $ analyzeDefault expr
  Branch _ _ ->
    complex NonTrivial $ analyzeDefault expr
  Fail _ ->
    complex NonTrivial $ analyzeDefault expr
  PrimOp _ ->
    complex NonTrivial $ analyzeDefault expr
  PrimEffect _ ->
    complex NonTrivial $ analyzeDefault expr
  Accessor hd _ ->
    case syntaxOf hd of
      Just (Accessor _ _) ->
        analysis
      Just (Var _) ->
        complex TopLevelDeref analysis
      _ ->
        complex Deref analysis
    where
    analysis = analyzeDefault expr
  Lit _ ->
    analyzeDefault expr

analyzeDefault :: forall a. HasAnalysis a => BackendSyntax a -> BackendAnalysis
analyzeDefault = bump <<< foldMap analysisOf
