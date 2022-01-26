-- | Extract all names and meta-variables from things.

module Agda.Syntax.Internal.Names where

import Data.List.NonEmpty (NonEmpty(..))
import Data.Map (Map)
import Data.Set (Set)

import Agda.Syntax.Common
import Agda.Syntax.Literal
import Agda.Syntax.Internal
import qualified Agda.Syntax.Concrete as C
import qualified Agda.Syntax.Abstract as A

import Agda.TypeChecking.Monad.Base
import Agda.TypeChecking.CompiledClause

import Agda.Utils.Singleton
import Agda.Utils.Impossible

-- | Some or all of the 'QName's that can be found in the given thing.

namesIn :: (NamesIn a, Collection QName m) => a -> m
namesIn = namesIn' singleton

-- | Some or all of the 'QName's that can be found in the given thing.

namesIn' :: (NamesIn a, Monoid m) => (QName -> m) -> a -> m
namesIn' f = namesAndMetasIn' (either f mempty)

-- | Some or all of the meta-variables that can be found in the given
-- thing.

metasIn :: (NamesIn a, Collection MetaId m) => a -> m
metasIn = metasIn' singleton

-- | Some or all of the meta-variables that can be found in the given
-- thing.

-- TODO: Does this function make
-- Agda.Syntax.Internal.MetaVars.allMetas superfluous? Maybe not,
-- allMetas ignores the first argument of PiSort.

metasIn' :: (NamesIn a, Monoid m) => (MetaId -> m) -> a -> m
metasIn' f = namesAndMetasIn' (either mempty f)

-- | Some or all of the names and meta-variables that can be found in
-- the given thing.

namesAndMetasIn ::
  (NamesIn a, Collection QName m1, Collection MetaId m2) =>
  a -> (m1, m2)
namesAndMetasIn =
  namesAndMetasIn'
    (either (\x -> (singleton x, mempty))
            (\m -> (mempty, singleton m)))

class NamesIn a where
  -- | Some or all of the names and meta-variables that can be found
  -- in the given thing.
  namesAndMetasIn' :: Monoid m => (Either QName MetaId -> m) -> a -> m

  default namesAndMetasIn' ::
    (Monoid m, Foldable f, NamesIn b, f b ~ a) =>
    (Either QName MetaId -> m) -> a -> m
  namesAndMetasIn' = foldMap . namesAndMetasIn'

-- Generic collections
instance NamesIn a => NamesIn (Maybe a)
instance NamesIn a => NamesIn [a]
instance NamesIn a => NamesIn (NonEmpty a)
instance NamesIn a => NamesIn (Set a)
instance NamesIn a => NamesIn (Map k a)

-- Decorations
instance NamesIn a => NamesIn (Arg a)
instance NamesIn a => NamesIn (Dom a)
instance NamesIn a => NamesIn (Named n a)
instance NamesIn a => NamesIn (Abs a)
instance NamesIn a => NamesIn (WithArity a)
instance NamesIn a => NamesIn (Open a)
instance NamesIn a => NamesIn (C.FieldAssignment' a)

-- Specific collections
instance NamesIn a => NamesIn (Tele a)

-- Tuples

instance (NamesIn a, NamesIn b) => NamesIn (a, b) where
  namesAndMetasIn' sg (x, y) =
    mappend (namesAndMetasIn' sg x) (namesAndMetasIn' sg y)

instance (NamesIn a, NamesIn b, NamesIn c) => NamesIn (a, b, c) where
  namesAndMetasIn' sg (x, y, z) = namesAndMetasIn' sg (x, (y, z))

instance (NamesIn a, NamesIn b, NamesIn c, NamesIn d) => NamesIn (a, b, c, d) where
  namesAndMetasIn' sg (x, y, z, u) =
    namesAndMetasIn' sg ((x, y), (z, u))

instance NamesIn CompKit where
  namesAndMetasIn' sg (CompKit a b) = namesAndMetasIn' sg (a,b)

-- Base cases

instance NamesIn QName where
  namesAndMetasIn' sg x = sg (Left x)  -- interesting case!

instance NamesIn MetaId where
  namesAndMetasIn' sg x = sg (Right x)

instance NamesIn ConHead where
  namesAndMetasIn' sg h = namesAndMetasIn' sg (conName h)

-- Andreas, 2017-07-27
-- In the following clauses, the choice of fields is not obvious
-- to the reader.  Please comment on the choices.
--
-- Also, this would be more robust if these were constructor-style
-- matches instead of record-style matches.
-- If someone adds a field containing names, this would go unnoticed.

instance NamesIn Definition where
  namesAndMetasIn' sg def =
    namesAndMetasIn' sg (defType def, theDef def, defDisplay def)

instance NamesIn Defn where
  namesAndMetasIn' sg = \case
    Axiom _            -> mempty
    DataOrRecSig{}     -> mempty
    GeneralizableVar{} -> mempty
    PrimitiveSort{}    -> mempty
    AbstractDefn{}     -> __IMPOSSIBLE__
    -- Andreas 2017-07-27, Q: which names can be in @cc@ which are not already in @cl@?
    Function    { funClauses = cl, funCompiled = cc }
      -> namesAndMetasIn' sg (cl, cc)
    Datatype    { dataClause = cl, dataCons = cs, dataSort = s, dataTranspIx = trX, dataTransp = trD }
      -> namesAndMetasIn' sg (cl, cs, s, (trX, trD))
    Record      { recClause = cl, recConHead = c, recFields = fs, recComp = comp }
      -> namesAndMetasIn' sg (cl, c, fs, comp)
      -- Don't need recTel since those will be reachable from the constructor
    Constructor { conSrcCon = c, conData = d, conComp = kit, conProj = fs }
      -> namesAndMetasIn' sg (c, d, kit, fs)
    Primitive   { primClauses = cl, primCompiled = cc }
      -> namesAndMetasIn' sg (cl, cc)

instance NamesIn Clause where
  namesAndMetasIn' sg
    Clause{ clauseTel = tel, namedClausePats = ps, clauseBody = b,
            clauseType = t } =
    namesAndMetasIn' sg (tel, ps, b, t)

instance NamesIn CompiledClauses where
  namesAndMetasIn' sg (Case _ c) = namesAndMetasIn' sg c
  namesAndMetasIn' sg (Done _ v) = namesAndMetasIn' sg v
  namesAndMetasIn' sg Fail{}     = mempty

-- Andreas, 2017-07-27
-- Why ignoring the litBranches?
instance NamesIn a => NamesIn (Case a) where
  namesAndMetasIn' sg Branches{ conBranches = bs, catchAllBranch = c } =
    namesAndMetasIn' sg (bs, c)

instance NamesIn (Pattern' a) where
  namesAndMetasIn' sg = \case
    VarP{}          -> mempty
    LitP _ l        -> namesAndMetasIn' sg l
    DotP _ v        -> namesAndMetasIn' sg v
    ConP c _ args   -> namesAndMetasIn' sg (c, args)
    DefP o q args   -> namesAndMetasIn' sg (q, args)
    ProjP _ f       -> namesAndMetasIn' sg f
    IApplyP _ t u _ -> namesAndMetasIn' sg (t, u)

instance NamesIn a => NamesIn (Type' a) where
  namesAndMetasIn' sg (El s t) = namesAndMetasIn' sg (s, t)

instance NamesIn Sort where
  namesAndMetasIn' sg = \case
    Type l      -> namesAndMetasIn' sg l
    Prop l      -> namesAndMetasIn' sg l
    Inf _ _     -> mempty
    SSet l      -> namesAndMetasIn' sg l
    SizeUniv    -> mempty
    LockUniv    -> mempty
    IntervalUniv -> mempty
    PiSort a b c  -> namesAndMetasIn' sg (a, b, c)
    FunSort a b -> namesAndMetasIn' sg (a, b)
    UnivSort a  -> namesAndMetasIn' sg a
    MetaS x es  -> namesAndMetasIn' sg (x, es)
    DefS d es   -> namesAndMetasIn' sg (d, es)
    DummyS{}    -> mempty

instance NamesIn Term where
  namesAndMetasIn' sg = \case
    Var _ args   -> namesAndMetasIn' sg args
    Lam _ b      -> namesAndMetasIn' sg b
    Lit l        -> namesAndMetasIn' sg l
    Def f args   -> namesAndMetasIn' sg (f, args)
    Con c _ args -> namesAndMetasIn' sg (c, args)
    Pi a b       -> namesAndMetasIn' sg (a, b)
    Sort s       -> namesAndMetasIn' sg s
    Level l      -> namesAndMetasIn' sg l
    MetaV x args -> namesAndMetasIn' sg (x, args)
    DontCare v   -> namesAndMetasIn' sg v
    Dummy{}      -> mempty

instance NamesIn Level where
  namesAndMetasIn' sg (Max _ ls) = namesAndMetasIn' sg ls

instance NamesIn PlusLevel where
  namesAndMetasIn' sg (Plus _ l) = namesAndMetasIn' sg l

-- For QName and Meta literals!
instance NamesIn Literal where
  namesAndMetasIn' sg = \case
    LitNat{}      -> mempty
    LitWord64{}   -> mempty
    LitString{}   -> mempty
    LitChar{}     -> mempty
    LitFloat{}    -> mempty
    LitQName    x -> namesAndMetasIn' sg x
    LitMeta _ m   -> namesAndMetasIn' sg m

instance NamesIn a => NamesIn (Elim' a) where
  namesAndMetasIn' sg (Apply arg)      = namesAndMetasIn' sg arg
  namesAndMetasIn' sg (Proj _ f)       = namesAndMetasIn' sg f
  namesAndMetasIn' sg (IApply x y arg) = namesAndMetasIn' sg (x, y, arg)

instance NamesIn DisplayForm where
  namesAndMetasIn' sg (Display _ ps v) = namesAndMetasIn' sg (ps, v)

instance NamesIn DisplayTerm where
  namesAndMetasIn' sg = \case
    DWithApp v us es -> namesAndMetasIn' sg (v, us, es)
    DCon c _ vs      -> namesAndMetasIn' sg (c, vs)
    DDef f es        -> namesAndMetasIn' sg (f, es)
    DDot v           -> namesAndMetasIn' sg v
    DTerm v          -> namesAndMetasIn' sg v

-- Pattern synonym stuff --

newtype PSyn = PSyn A.PatternSynDefn
instance NamesIn PSyn where
  namesAndMetasIn' sg (PSyn (_args, p)) = namesAndMetasIn' sg p

instance NamesIn (A.Pattern' a) where
  namesAndMetasIn' sg = \case
    A.VarP{}               -> mempty
    A.ConP _ c args        -> namesAndMetasIn' sg (c, args)
    A.ProjP _ _ d          -> namesAndMetasIn' sg d
    A.DefP _ f args        -> namesAndMetasIn' sg (f, args)
    A.WildP{}              -> mempty
    A.AsP _ _ p            -> namesAndMetasIn' sg p
    A.AbsurdP{}            -> mempty
    A.LitP _ l             -> namesAndMetasIn' sg l
    A.PatternSynP _ c args -> namesAndMetasIn' sg (c, args)
    A.RecP _ fs            -> namesAndMetasIn' sg fs
    A.DotP{}               -> __IMPOSSIBLE__    -- Dot patterns are not allowed in pattern synonyms
    A.EqualP{}             -> __IMPOSSIBLE__    -- Andrea: should we allow these in pattern synonyms?
    A.WithP _ p            -> namesAndMetasIn' sg p
    A.AnnP _ a p           -> __IMPOSSIBLE__    -- Type annotations are not (yet) allowed in pattern synonyms

instance NamesIn AmbiguousQName where
  namesAndMetasIn' sg (AmbQ cs) = namesAndMetasIn' sg cs
