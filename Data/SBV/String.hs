{-# LANGUAGE Rank2Types          #-}
{-# LANGUAGE OverloadedStrings   #-}
{-# LANGUAGE ScopedTypeVariables #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Data.SBV.String
-- Copyright   :  (c) Joel Burget, Levent Erkok
-- License     :  BSD3
-- Maintainer  :  erkokl@gmail.com
-- Stability   :  experimental
--
-- A collection of string/character utilities, useful when working
-- with symbolic strings. To the extent possible, the functions
-- in this module follow those of "Data.List" so importing qualified
-- is the recommended workflow. Also, it is recommended you use the
-- @OverloadedStrings@ extension to allow literal strings to be
-- used as symbolic-strings.
-----------------------------------------------------------------------------

module Data.SBV.String (
        -- * Length, emptiness
          length, null
        -- * Deconstructing/Reconstructing
        , head, tail, charToStr, strToStrAt, strToCharAt, (.!!), implode, concat, (.++)
        -- * Containment
        , isInfixOf, isSuffixOf, isPrefixOf
        -- * Substrings
        , take, drop, subStr, replace, indexOf, offsetIndexOf
        -- * Conversion to\/from naturals
        , strToNat, natToStr
        ) where

import Prelude hiding (head, tail, length, take, drop, concat, null)
import qualified Prelude as P

import Data.SBV.Core.Data
import Data.SBV.Core.Model

import qualified Data.Char as C
import Data.List (genericLength, genericIndex, genericDrop, genericTake)
import qualified Data.List as L (tails, isSuffixOf, isPrefixOf, isInfixOf)

-- For doctest use only
--
-- $setup
-- >>> import Data.SBV.Provers.Prover (prove, sat)
-- >>> import Data.SBV.Utils.Boolean  ((==>), (&&&), bnot, (<=>))
-- >>> :set -XOverloadedStrings

-- | Length of a string.
--
-- >>> sat $ \s -> length s .== 2
-- Satisfiable. Model:
--   s0 = "\NUL\NUL" :: String
-- >>> sat $ \s -> length s .< 0
-- Unsatisfiable
-- >>> prove $ \s1 s2 -> length s1 + length s2 .== length (s1 .++ s2)
-- Q.E.D.
length :: SString -> SInteger
length = lift1 StrLen (Just (fromIntegral . P.length))

-- | @`null` s@ is True iff the string is empty
--
-- >>> prove $ \s -> null s <=> length s .== 0
-- Q.E.D.
-- >>> prove $ \s -> null s <=> s .== ""
-- Q.E.D.
null :: SString -> SBool
null s
  | Just cs <- unliteral s
  = literal (P.null cs)
  | True
  = s .== literal ""

-- | @`head`@ returns the head of a string. Unspecified if the string is empty.
--
-- >>> prove $ \c -> head (charToStr c) .== c
-- Q.E.D.
head :: SString -> SChar
head = (`strToCharAt` 0)

-- | @`tail`@ returns the tail of a string. Unspecified if the string is empty.
--
-- >>> prove $ \h s -> tail (charToStr h .++ s) .== s
-- Q.E.D.
-- >>> prove $ \s -> length s .> 0 ==> length (tail s) .== length s - 1
-- Q.E.D.
-- >>> prove $ \s -> bnot (null s) ==> charToStr (head s) .++ tail s .== s
-- Q.E.D.
tail :: SString -> SString
tail s
 | Just (_:cs) <- unliteral s
 = literal cs
 | True
 = subStr s 1 (length s - 1)

-- | @`charToStr` c@ is the string of length 1 that contains the only character
-- whose value is the 8-bit value @c@.
--
-- >>> prove $ \c -> c .== literal 'A' ==> charToStr c .== "A"
-- Q.E.D.
-- >>> prove $ \c -> length (charToStr c) .== 1
-- Q.E.D.
charToStr :: SChar -> SString
charToStr = lift1 StrUnit (Just wrap)
  where wrap c = [c]

-- | @`strToStrAt` s offset@. Substring of length 1 at @offset@ in @s@. Unspecified if
-- index is out of bounds.
--
-- >>> prove $ \s1 s2 -> strToStrAt (s1 .++ s2) (length s1) .== strToStrAt s2 0
-- Q.E.D.
-- >>> sat $ \s -> length s .>= 2 &&& strToStrAt s 0 ./= strToStrAt s (length s - 1)
-- Satisfiable. Model:
--   s0 = "\NUL\NUL " :: String
strToStrAt :: SString -> SInteger -> SString
strToStrAt s offset = subStr s offset 1

-- | @`strToCharAt` s i@ is the 8-bit value stored at location @i@. Unspecified if
-- index is out of bounds.
--
-- >>> prove $ \i -> i .>= 0 &&& i .<= 4 ==> "AAAAA" `strToCharAt` i .== literal 'A'
-- Q.E.D.
-- >>> prove $ \s i c -> s `strToCharAt` i .== c ==> indexOf s (charToStr c) .<= i
-- Q.E.D.
strToCharAt :: SString -> SInteger -> SChar
strToCharAt s i
  | Just cs <- unliteral s, Just ci <- unliteral i, ci >= 0, ci < genericLength cs, let c = C.ord (cs `genericIndex` ci)
  = literal (C.chr c)
  | True
  = SBV (SVal w8 (Right (cache (y (s `strToStrAt` i)))))
  where w8      = KBounded False 8
        -- This is trickier than it needs to be, but necessary since there's
        -- no SMTLib function to extract the character from a string. Instead,
        -- we form a singleton string, and assert that it is equivalent to
        -- the extracted value. See <http://github.com/Z3Prover/z3/issues/1302>
        y si st = do c <- internalVariable st w8
                     cs <- newExpr st KString (SBVApp (StrOp StrUnit) [c])
                     let csSBV = SBV (SVal KString (Right (cache (\_ -> return cs))))
                     internalConstraint st Nothing $ unSBV $ csSBV .== si
                     return c

-- | Short cut for 'strToCharAt'
(.!!) :: SString -> SInteger -> SChar
(.!!) = strToCharAt

-- | @`implode` cs@ is the string of length @|cs|@ containing precisely those
-- characters. Note that there is no corresponding function @explode@, since
-- we wouldn't know the length of a symbolic string.
--
-- >>> prove $ \c1 c2 c3 -> length (implode [c1, c2, c3]) .== 3
-- Q.E.D.
-- >>> prove $ \c1 c2 c3 -> map (strToCharAt (implode [c1, c2, c3])) (map literal [0 .. 2]) .== [c1, c2, c3]
-- Q.E.D.
implode :: [SChar] -> SString
implode = foldr ((.++) . charToStr) ""

-- | Concatenate two strings. See also `.++`.
concat :: SString -> SString -> SString
concat x y | isConcretelyEmpty x = y
           | isConcretelyEmpty y = x
           | True                = lift2 StrConcat (Just (++)) x y

-- | Short cut for `concat`.
--
-- >>> sat $ \x y z -> length x .== 5 &&& length y .== 1 &&& x .++ y .++ z .== "Hello world!"
-- Satisfiable. Model:
--   s0 =  "Hello" :: String
--   s1 =      " " :: String
--   s2 = "world!" :: String
infixr 5 .++
(.++) :: SString -> SString -> SString
(.++) = concat

-- | @`isInfixOf` sub s@. Does @s@ contain the substring @sub@?
--
-- >>> prove $ \s1 s2 s3 -> s2 `isInfixOf` (s1 .++ s2 .++ s3)
-- Q.E.D.
-- >>> prove $ \s1 s2 -> s1 `isInfixOf` s2 &&& s2 `isInfixOf` s1 <=> s1 .== s2
-- Q.E.D.
isInfixOf :: SString -> SString -> SBool
sub `isInfixOf` s
  | isConcretelyEmpty sub
  = literal True
  | True
  = lift2 StrContains (Just (flip L.isInfixOf)) s sub -- NB. flip, since `StrContains` takes args in rev order!

-- | @`isPrefixOf` pre s@. Is @pre@ a prefix of @s@?
--
-- >>> prove $ \s1 s2 -> s1 `isPrefixOf` (s1 .++ s2)
-- Q.E.D.
-- >>> prove $ \s1 s2 -> s1 `isPrefixOf` s2 ==> subStr s2 0 (length s1) .== s1
-- Q.E.D.
isPrefixOf :: SString -> SString -> SBool
pre `isPrefixOf` s
  | isConcretelyEmpty pre
  = literal True
  | True
  = lift2 StrPrefixOf (Just L.isPrefixOf) pre s

-- | @`isSuffixOf` suf s@. Is @suf@ a suffix of @s@?
--
-- >>> prove $ \s1 s2 -> s2 `isSuffixOf` (s1 .++ s2)
-- Q.E.D.
-- >>> prove $ \s1 s2 -> s1 `isSuffixOf` s2 ==> subStr s2 (length s2 - length s1) (length s1) .== s1
-- Q.E.D.
isSuffixOf :: SString -> SString -> SBool
suf `isSuffixOf` s
  | isConcretelyEmpty suf
  = literal True
  | True
  = lift2 StrSuffixOf (Just L.isSuffixOf) suf s

-- | @`take` len s@. Corresponds to Haskell's `take` on symbolic-strings.
--
-- >>> prove $ \s i -> i .>= 0 ==> length (take i s) .<= i
-- Q.E.D.
take :: SInteger -> SString -> SString
take i s = ite (i .<= 0)        (literal "")
         $ ite (i .>= length s) s
         $ subStr s 0 i

-- | @`drop` len s@. Corresponds to Haskell's `drop` on symbolic-strings.
--
-- >>> prove $ \s i -> length (drop i s) .<= length s
-- Q.E.D.
-- >>> prove $ \s i -> take i s .++ drop i s .== s
-- Q.E.D.
drop :: SInteger -> SString -> SString
drop i s = ite (i .>= ls) (literal "")
         $ ite (i .<= 0)  s
         $ subStr s i (ls - i)
  where ls = length s

-- | @`subStr` s offset len@ is the substring of @s@ at offset `offset` with length `len`.
-- This function is under-specified when the offset is outside the range of positions in @s@ or @len@
-- is negative or @offset+len@ exceeds the length of @s@. For a friendlier version of this function
-- that acts like Haskell's `take`\/`drop`, see `strTake`\/`strDrop`.
--
-- >>> prove $ \s i -> i .>= 0 &&& i .< length s ==> subStr s 0 i .++ subStr s i (length s - i) .== s
-- Q.E.D.
-- >>> sat  $ \i j -> subStr "hello" i j .== "ell"
-- Satisfiable. Model:
--   s0 = 1 :: Integer
--   s1 = 3 :: Integer
-- >>> sat  $ \i j -> subStr "hell" i j .== "no"
-- Unsatisfiable
subStr :: SString -> SInteger -> SInteger -> SString
subStr s offset len
  | Just c <- unliteral s                    -- a constant string
  , Just o <- unliteral offset               -- a constant offset
  , Just l <- unliteral len                  -- a constant length
  , let lc = genericLength c                 -- length of the string
  , let valid x = x >= 0 && x <= lc          -- predicate that checks valid point
  , valid o                                  -- offset is valid
  , l >= 0                                   -- length is not-negative
  , valid $ o + l                            -- we don't overrun
  = literal $ genericTake l $ genericDrop o c
  | True                                     -- either symbolic, or something is out-of-bounds
  = lift3 StrSubstr Nothing s offset len

-- | @`replace` s src dst@. Replace the first occurrence of @src@ by @dst@ in @s@
--
-- >>> prove $ \s -> replace "hello" s "world" .== "world" ==> s .== "hello"
-- Q.E.D.
-- >>> prove $ \s1 s2 s3 -> length s2 .> length s1 ==> replace s1 s2 s3 .== s1
-- Q.E.D.
replace :: SString -> SString -> SString -> SString
replace s src dst
  | Just b <- unliteral src, P.null b   -- If src is null, simply prepend
  = dst .++ s
  | Just a <- unliteral s
  , Just b <- unliteral src
  , Just c <- unliteral dst
  = literal $ walk a b c
  | True
  = lift3 StrReplace Nothing s src dst
  where walk haystack needle newNeedle = go haystack   -- note that needle is guaranteed non-empty here.
           where go []       = []
                 go i@(c:cs)
                  | needle `L.isPrefixOf` i = newNeedle ++ genericDrop (genericLength needle :: Integer) i
                  | True                    = c : go cs

-- | @`indexOf` s sub@. Retrieves first position of @sub@ in @s@, @-1@ if there are no occurrences.
-- Equivalent to @`offsetIndexOf` s sub 0@.
--
-- >>> prove $ \s i -> i .> 0 &&& i .< length s ==> indexOf s (subStr s i 1) .<= i
-- Q.E.D.
-- >>> prove $ \s i -> i .> 0 &&& i .< length s ==> indexOf s (subStr s i 1) .== i
-- Falsifiable. Counter-example:
--   s0 = "\NUL\NUL\NUL" :: String
--   s1 =              2 :: Integer
-- >>> prove $ \s1 s2 -> length s2 .> length s1 ==> indexOf s1 s2 .== -1
-- Q.E.D.
indexOf :: SString -> SString -> SInteger
indexOf s sub = offsetIndexOf s sub 0

-- | @`offsetIndexOf` s sub offset@. Retrieves first position of @sub@ at or
-- after @offset@ in @s@, @-1@ if there are no occurrences.
--
-- >>> prove $ \s sub -> offsetIndexOf s sub 0 .== indexOf s sub
-- Q.E.D.
-- >>> prove $ \s sub i -> i .>= length s &&& length sub .> 0 ==> offsetIndexOf s sub i .== -1
-- Q.E.D.
-- >>> prove $ \s sub i -> i .> length s ==> offsetIndexOf s sub i .== -1
-- Q.E.D.
offsetIndexOf :: SString -> SString -> SInteger -> SInteger
offsetIndexOf s sub offset
  | Just c <- unliteral s               -- a constant string
  , Just n <- unliteral sub             -- a constant search pattern
  , Just o <- unliteral offset          -- at a constant offset
  , o >= 0, o <= genericLength c        -- offset is good
  = case [i | (i, t) <- zip [o ..] (L.tails (genericDrop o c)), n `L.isPrefixOf` t] of
      (i:_) -> literal i
      _     -> -1
  | True
  = lift3 StrIndexOf Nothing s sub offset

-- | @`strToNat` s@. Retrieve integer encoded by string @s@ (ground rewriting only).
-- Note that by definition this function only works when 's' only contains digits,
-- that is, if it encodes a natural number. Otherwise, it returns '-1'.
-- See <http://cvc4.cs.stanford.edu/wiki/Strings> for details.
--
-- >>> prove $ \s -> let n = strToNat s in n .>= 0 &&& n .< 10 ==> length s .== 1
-- Q.E.D.
strToNat :: SString -> SInteger
strToNat s
 | Just a <- unliteral s
 = if all C.isDigit a && not (P.null a)
   then literal (read a)
   else -1
 | True
 = lift1 StrStrToNat Nothing s

-- | @`natToStr` i@. Retrieve string encoded by integer @i@ (ground rewriting only).
-- Again, only naturals are supported, any input that is not a natural number
-- produces empty string, even though we take an integer as an argument.
-- See <http://cvc4.cs.stanford.edu/wiki/Strings> for details.
--
-- >>> prove $ \i -> length (natToStr i) .== 3 ==> i .<= 999
-- Q.E.D.
natToStr :: SInteger -> SString
natToStr i
 | Just v <- unliteral i
 = literal $ if v >= 0 then show v else ""
 | True
 = lift1 StrNatToStr Nothing i

-- | Lift a unary operator over strings.
lift1 :: forall a b. (SymWord a, SymWord b) => StrOp -> Maybe (a -> b) -> SBV a -> SBV b
lift1 w mbOp a
  | Just cv <- concEval1 mbOp a
  = cv
  | True
  = SBV $ SVal k $ Right $ cache r
  where k = kindOf (undefined :: b)
        r st = do swa <- sbvToSW st a
                  newExpr st k (SBVApp (StrOp w) [swa])

-- | Lift a binary operator over strings.
lift2 :: forall a b c. (SymWord a, SymWord b, SymWord c) => StrOp -> Maybe (a -> b -> c) -> SBV a -> SBV b -> SBV c
lift2 w mbOp a b
  | Just cv <- concEval2 mbOp a b
  = cv
  | True
  = SBV $ SVal k $ Right $ cache r
  where k = kindOf (undefined :: c)
        r st = do swa <- sbvToSW st a
                  swb <- sbvToSW st b
                  newExpr st k (SBVApp (StrOp w) [swa, swb])

-- | Lift a ternary operator over strings.
lift3 :: forall a b c d. (SymWord a, SymWord b, SymWord c, SymWord d) => StrOp -> Maybe (a -> b -> c -> d) -> SBV a -> SBV b -> SBV c -> SBV d
lift3 w mbOp a b c
  | Just cv <- concEval3 mbOp a b c
  = cv
  | True
  = SBV $ SVal k $ Right $ cache r
  where k = kindOf (undefined :: d)
        r st = do swa <- sbvToSW st a
                  swb <- sbvToSW st b
                  swc <- sbvToSW st c
                  newExpr st k (SBVApp (StrOp w) [swa, swb, swc])

-- | Concrete evaluation for unary ops
concEval1 :: (SymWord a, SymWord b) => Maybe (a -> b) -> SBV a -> Maybe (SBV b)
concEval1 mbOp a = literal <$> (mbOp <*> unliteral a)

-- | Concrete evaluation for binary ops
concEval2 :: (SymWord a, SymWord b, SymWord c) => Maybe (a -> b -> c) -> SBV a -> SBV b -> Maybe (SBV c)
concEval2 mbOp a b = literal <$> (mbOp <*> unliteral a <*> unliteral b)

-- | Concrete evaluation for ternary ops
concEval3 :: (SymWord a, SymWord b, SymWord c, SymWord d) => Maybe (a -> b -> c -> d) -> SBV a -> SBV b -> SBV c -> Maybe (SBV d)
concEval3 mbOp a b c = literal <$> (mbOp <*> unliteral a <*> unliteral b <*> unliteral c)

-- | Is the string concretely known empty?
isConcretelyEmpty :: SString -> Bool
isConcretelyEmpty ss | Just s <- unliteral ss = P.null s
                     | True                   = False
