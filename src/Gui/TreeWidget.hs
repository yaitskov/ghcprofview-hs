{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE OverloadedLabels #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}

module Gui.TreeWidget where

import Control.Monad
import qualified Data.Text as T

import Data.GI.Base.GType
import Data.GI.Base.GValue
import GI.Gtk 

import Types

data ColumnType =
    TextColumn
  | PercentColumn
  deriving (Eq, Show)

data Column a = Column {
    columnTitle :: T.Text
  , columnGType :: GType
  , columnType :: ColumnType
  , columnData :: a -> IO GValue
  }

newtype TreeWidgetConfig a = TreeWidgetConfig {
        twcColumns :: [Column a]
      }

mkTreeStore :: forall a t . IsTree t a => TreeWidgetConfig a -> t -> IO TreeStore
mkTreeStore cfg tree = do
    let columns = twcColumns cfg
    let gtypes = map columnGType columns
    store <- treeStoreNew gtypes
    fill store Nothing tree
    return store
  where
    fill :: TreeStore -> Maybe TreeIter -> t -> IO ()
    fill store root node = do
      let cc = treeRoot node
      item <- treeStoreInsert store root (negate 1)
      forM_ (zip [0..] (twcColumns cfg)) $ \(i, column) ->
          treeStoreSetValue store item i =<< columnData column cc
      forM_ (treeChildren node) $ fill store (Just item)
  
mkTreeView :: forall t a . IsTree t a => TreeWidgetConfig a -> t -> IO TreeView
mkTreeView cfg@(TreeWidgetConfig columns) tree = do
    srcStore <- mkTreeStore cfg tree
    store <- treeModelSortNewWithModel srcStore
    view <- treeViewNewWithModel store
    treeViewSetHeadersVisible view True
    forM_ (zip [0..] columns) $ \(i, column) ->
      addColumn view i (columnType column) (columnTitle column)

    return view
  where
    addColumn view i ctype title = do
      column <- treeViewColumnNew
      treeViewColumnSetTitle column title
      withRenderer ctype $ \renderer -> do
        treeViewColumnPackStart column renderer True
        let propName = getPropName ctype
        treeViewColumnAddAttribute column renderer propName i
        set column [ #resizable := True ]
        treeViewColumnSetSizing column TreeViewColumnSizingFixed
        treeViewColumnSetSortColumnId column i
        treeViewAppendColumn view column

      button <- treeViewColumnGetButton column
      on button #buttonPressEvent $ \ev -> do
        button <- get ev #button
        when (button == 3) $ do
          menu <- mkColumnsMenu view
          menuPopupAtPointer menu Nothing
        return True

    withRenderer :: ColumnType -> (forall r. IsCellRenderer r => r -> IO x) -> IO x
    withRenderer TextColumn f = cellRendererTextNew >>= f
    withRenderer PercentColumn f = cellRendererProgressNew >>= f

    getPropName TextColumn = "text"
    getPropName PercentColumn = "value"

mkColumnsMenu :: TreeView -> IO Menu
mkColumnsMenu tree = do
    menu <- menuNew
    columns <- treeViewGetColumns tree
    forM_ (zip [0..] columns) $ \(i, column) -> do
      title <- treeViewColumnGetTitle column
      item <- checkMenuItemNewWithLabel title
      menuShellAppend menu item
      widgetShow item
      visible <- treeViewColumnGetVisible column
      checkMenuItemSetActive item visible
      on item #activate $ do
        treeViewColumnSetVisible column (not visible)
    return menu

