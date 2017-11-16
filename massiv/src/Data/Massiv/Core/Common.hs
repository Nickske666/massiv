{-# LANGUAGE BangPatterns          #-}
{-# LANGUAGE FlexibleContexts      #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE TypeFamilies          #-}
{-# LANGUAGE UndecidableInstances  #-}
-- |
-- Module      : Data.Massiv.Core.Common
-- Copyright   : (c) Alexey Kuleshevich 2017
-- License     : BSD3
-- Maintainer  : Alexey Kuleshevich <lehins@yandex.ru>
-- Stability   : experimental
-- Portability : non-portable
--
module Data.Massiv.Core.Common
  ( Array
  , Elt
  , EltRepr
  , Construct(..)
  , Source(..)
  , Load(..)
  , Size(..)
  , Slice(..)
  , OuterSlice(..)
  , InnerSlice(..)
  , Manifest(..)
  , Mutable(..)
  , Ragged(..)
  , Nested(..)
  , NestedStruct
  , makeArray
  , singleton
  -- * Indexing
  , (!)
  , index
  , (!?)
  , maybeIndex
  , (??)
  , defaultIndex
  , borderIndex
  , evaluateAt
  , module Data.Massiv.Core.Index
  , module Data.Massiv.Core.Computation
  ) where

import           Control.Monad.Primitive      (PrimMonad (..))
import           Data.Massiv.Core.Computation
import           Data.Massiv.Core.Index
import           Data.Typeable

-- | The array family. All array representations @r@ describe how data is
-- arranged. All arrays have a common property that each index @ix@ always maps
-- to the same unique element, even if that element does not exist in memory and
-- has to be computed upon lookup. Data is always arranged in a nested fasion,
-- depth of which is controlled by @`Rank` ix@.
data family Array r ix e :: *

type family EltRepr r ix :: *

type family Elt r ix e :: * where
  Elt r Ix1 e = e
  Elt r ix  e = Array (EltRepr r ix) (Lower ix) e

type family NestedStruct r ix e :: *

-- | Index polymorphic arrays.
class (Typeable r, Index ix) => Construct r ix e where

  getComp :: Array r ix e -> Comp

  setComp :: Comp -> Array r ix e -> Array r ix e

  unsafeMakeArray :: Comp -> ix -> (ix -> e) -> Array r ix e

class Construct r ix e => Size r ix e where

  -- | /O(1)/ - Get the size of an array
  size :: Array r ix e -> ix

  unsafeResize :: Index ix' => ix' -> Array r ix e -> Array r ix' e

  unsafeExtract :: ix -> ix -> Array r ix e -> Array (EltRepr r ix) ix e


class Size r ix e => Source r ix e where

  unsafeIndex :: Array r ix e -> ix -> e
  unsafeIndex !arr = unsafeLinearIndex arr . toLinearIndex (size arr)
  {-# INLINE unsafeIndex #-}

  unsafeLinearIndex :: Array r ix e -> Int -> e
  unsafeLinearIndex !arr = unsafeIndex arr . fromLinearIndex (size arr)
  {-# INLINE unsafeLinearIndex #-}


class Size r ix e => Load r ix e where
  -- | Load an array into memory sequentially
  loadS
    :: Monad m =>
       Array r ix e -- ^ Array that is being loaded
    -> (Int -> m e) -- ^ Function that reads an element from target array
    -> (Int -> e -> m ()) -- ^ Function that writes an element into target array
    -> m ()

  -- | Load an array into memory in parallel
  loadP
    :: [Int] -- ^ List of capabilities to run workers on, as described in
             -- `Control.Concurrent.forkOn`. Empty list will imply all
             -- capabilities, i.e. run on all cores available through @+RTS -N@.
    -> Array r ix e -- ^ Array that is being loaded
    -> (Int -> IO e) -- ^ Function that reads an element from target array
    -> (Int -> e -> IO ()) -- ^ Function that writes an element into target array
    -> IO ()

class Size r ix e => OuterSlice r ix e where
  unsafeOuterSlice :: Array r ix e -> (Int, Lower ix) -> Int -> Elt r ix e

class Size r ix e => InnerSlice r ix e where
  unsafeInnerSlice :: Array r ix e -> (Lower ix, Int) -> Int -> Elt r ix e

class (InnerSlice r ix e, OuterSlice r ix e) => Slice r ix e where
  unsafeSlice :: Array r ix e -> ix -> ix -> Dim -> Maybe (Elt r ix e)


-- | Manifest arrays are backed by actual memory and values are looked up versus
-- computed as it is with delayed arrays. Because of this fact indexing functions
-- `(!)`, `(!?)`, etc. are constrained to manifest arrays only.
class Source r ix e => Manifest r ix e where

  unsafeLinearIndexM :: Array r ix e -> Int -> e


class Manifest r ix e => Mutable r ix e where
  data MArray s r ix e :: *

  -- | Get the size of a mutable array.
  msize :: MArray s r ix e -> ix

  unsafeThaw :: PrimMonad m =>
                Array r ix e -> m (MArray (PrimState m) r ix e)

  unsafeFreeze :: PrimMonad m =>
                  Comp -> MArray (PrimState m) r ix e -> m (Array r ix e)

  unsafeNew :: PrimMonad m =>
               ix -> m (MArray (PrimState m) r ix e)

  unsafeLinearRead :: PrimMonad m =>
                      MArray (PrimState m) r ix e -> Int -> m e

  unsafeLinearWrite :: PrimMonad m =>
                       MArray (PrimState m) r ix e -> Int -> e -> m ()



class Nested r ix e where
  fromNested :: NestedStruct r ix e -> Array r ix e

  toNested :: Array r ix e -> NestedStruct r ix e


class Construct r ix e => Ragged r ix e where

  empty :: Comp -> Array r ix e

  isNull :: Array r ix e -> Bool

  cons :: Elt r ix e -> Array r ix e -> Array r ix e

  uncons :: Array r ix e -> Maybe (Elt r ix e, Array r ix e)

  unsafeGenerateM :: Monad m => Comp -> ix -> (ix -> m e) -> m (Array r ix e)

  edgeSize :: Array r ix e -> ix

  outerLength :: Array r ix e -> Int

  flatten :: Array r ix e -> Array r Ix1 e

  loadRagged ::
    (IO () -> IO ()) -> (Int -> e -> IO a) -> Int -> Int -> Lower ix -> Array r ix e -> IO ()

  -- TODO: test property:
  -- (read $ raggedFormat show "\n" (ls :: Array L (IxN n) Int)) == ls
  raggedFormat :: (e -> String) -> String -> Array r ix e -> String



-- | Create an Array.
makeArray :: Construct r ix e =>
             Comp -- ^ Computation strategy. Useful constructors are `Seq` and `Par`
          -> ix -- ^ Size of the result Array
          -> (ix -> e) -- ^ Function to generate elements at a particular index
          -> Array r ix e
makeArray !c = unsafeMakeArray c . liftIndex (max 0)
{-# INLINE makeArray #-}


-- | Create an Array with a single element.
singleton :: Construct r ix e =>
             Comp -- ^ Computation strategy
          -> e -- ^ The element
          -> Array r ix e
singleton !c = unsafeMakeArray c oneIndex . const
{-# INLINE singleton #-}


infixl 4 !, !?, ??

-- | Infix version of `index`.
(!) :: Manifest r ix e => Array r ix e -> ix -> e
(!) = index
{-# INLINE (!) #-}


-- | Infix version of `maybeIndex`.
(!?) :: Manifest r ix e => Array r ix e -> ix -> Maybe e
(!?) = maybeIndex
{-# INLINE (!?) #-}


-- | /O(1)/ - Lookup an element in the array, where array can itself be
-- `Nothing`. This operator is useful when used together with slicing or other
-- functions that return `Maybe` array:
--
-- >>> (fromList Seq [[[1,2,3]],[[4,5,6]]] :: Maybe (Array U Ix3 Int)) ??> 1 ?? (0 :. 2)
-- Just 6
--
(??) :: Manifest r ix e => Maybe (Array r ix e) -> ix -> Maybe e
(??) Nothing    = const Nothing
(??) (Just arr) = (arr !?)
{-# INLINE (??) #-}

-- | /O(1)/ - Lookup an element in the array. Returns `Nothing`, when index is out
-- of bounds, `Just` element otherwise.
maybeIndex :: Manifest r ix e => Array r ix e -> ix -> Maybe e
maybeIndex arr = handleBorderIndex (Fill Nothing) (size arr) (Just . unsafeIndex arr)
{-# INLINE maybeIndex #-}

-- | /O(1)/ - Lookup an element in the array, while using default element when
-- index is out of bounds.
defaultIndex :: Manifest r ix e => e -> Array r ix e -> ix -> e
defaultIndex defVal = borderIndex (Fill defVal)
{-# INLINE defaultIndex #-}

-- | /O(1)/ - Lookup an element in the array. Use a border resolution technique
-- when index is out of bounds.
borderIndex :: Manifest r ix e => Border e -> Array r ix e -> ix -> e
borderIndex border arr = handleBorderIndex border (size arr) (unsafeIndex arr)
{-# INLINE borderIndex #-}

-- | /O(1)/ - Lookup an element in the array. Throw an error if index is out of bounds.
index :: Manifest r ix e => Array r ix e -> ix -> e
index arr ix =
  borderIndex (Fill (errorIx "Data.Massiv.Array.index" (size arr) ix)) arr ix
{-# INLINE index #-}


-- | This is just like `index` function, but it allows getting values from
-- delayed arrays as well as manifest. As the name suggests, indexing into a
-- delayed array at the same index multiple times will cause evaluation of the
-- value each time and can destroy the performace if used without care.
evaluateAt :: Source r ix e => Array r ix e -> ix -> e
evaluateAt !arr !ix =
  handleBorderIndex
    (Fill (errorIx "Data.Massiv.Array.evaluateAt" (size arr) ix))
    (size arr)
    (unsafeIndex arr)
    ix
{-# INLINE evaluateAt #-}
