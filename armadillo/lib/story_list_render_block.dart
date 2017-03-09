// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:math' as math;
import 'dart:ui' show lerpDouble, ImageFilter;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'story_cluster_widget.dart' show InlineStoryTitle;
import 'story_list_layout.dart';
import 'story_list_render_block_parent_data.dart';

/// Set to true to slide the unfocused children of [StoryListRenderBlock] as the
/// focused child grows.
const bool _kSlideUnfocusedAway = true;

/// The distance in the Y direction to slide the unfocused children of
/// [StoryListRenderBlock] as the focused child grows.
const double _kSlideUnfocusedAwayOffsetY = -200.0;

/// The unfocused children of [StoryListRenderBlock] should be fully transparent
/// when the focused child's focus progress reaches this value and beyond.
const double _kFocusProgressWhenUnfocusedFullyTransparent = 0.7;

/// The ratio to use when converting the alpha of the scrim color to the
/// gaussian blur sigma values.
const double _kAlphaToBlurRatio = 1 / 25;

/// If true, children behind the scrim will be blurred.
const bool _kBlurScrimmedChildren = true;

/// Overrides [RenderBlock]'s layout, paint, and hit-test behaviour to allow
/// the following:
///   1) Stories are laid out as specified by [StoryListLayout].
///   2) A story expands as it comes into focus and shrinks when it leaves
///      focus.
///   3) Focused stories are above and overlap non-focused stories.
class StoryListRenderBlock extends RenderBlock {
  StoryListRenderBlock({
    List<RenderBox> children,
    Size parentSize,
    ScrollController scrollController,
    double bottomPadding,
    double listHeight,
    Color scrimColor,
    double liftScale,
    bool blurScrimmedChildren,
  })
      : _parentSize = parentSize,
        _scrollController = scrollController,
        _bottomPadding = bottomPadding ?? 0.0,
        _listHeight = listHeight ?? 0.0,
        _scrimColor = scrimColor ?? new Color(0x00000000),
        _liftScale = liftScale ?? 1.0,
        _blurScrimmedChildren = blurScrimmedChildren ?? _kBlurScrimmedChildren,
        super(children: children, mainAxis: Axis.vertical);

  bool get blurScrimmedChildren => _blurScrimmedChildren;
  bool _blurScrimmedChildren;
  set blurScrimmedChildren(bool value) {
    if (_blurScrimmedChildren != (value ?? _kBlurScrimmedChildren)) {
      _blurScrimmedChildren = (value ?? _kBlurScrimmedChildren);
      markNeedsPaint();
    }
  }

  Color get scrimColor => _scrimColor;
  Color _scrimColor;
  set scrimColor(Color value) {
    if (_scrimColor != value) {
      _scrimColor = value;
      markNeedsPaint();
    }
  }

  Size get parentSize => _parentSize;
  Size _parentSize;
  set parentSize(Size value) {
    if (_parentSize != value) {
      _parentSize = value;
      markNeedsLayout();
    }
  }

  ScrollController get scrollController => _scrollController;
  ScrollController _scrollController;
  set scrollController(ScrollController value) {
    if (_scrollController != value) {
      _scrollController = value;
      markNeedsLayout();
    }
  }

  double get bottomPadding => _bottomPadding;
  double _bottomPadding;
  set bottomPadding(double value) {
    if (_bottomPadding != value) {
      _bottomPadding = value;
      markNeedsLayout();
    }
  }

  double get listHeight => _listHeight;
  double _listHeight;
  set listHeight(double value) {
    if (_listHeight != value) {
      _listHeight = value;
      markNeedsLayout();
    }
  }

  double get liftScale => _liftScale;
  double _liftScale;
  set liftScale(double value) {
    if (_liftScale != value) {
      _liftScale = value;
      markNeedsLayout();
    }
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! StoryListRenderBlockParentData) {
      child.parentData = new StoryListRenderBlockParentData(this);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    List<RenderBox> childrenSortedByFocusProgress =
        _childrenSortedByFocusProgress;
    if (childrenSortedByFocusProgress.isEmpty) {
      return;
    }
    final RenderBox lastChild = childrenSortedByFocusProgress.last;
    childrenSortedByFocusProgress.remove(lastChild);
    final StoryListRenderBlockParentData mostFocusedChildParentData =
        lastChild.parentData;
    int unfocusedAlpha = (lerpDouble(
                1.0,
                0.0,
                mostFocusedChildParentData.focusProgress.clamp(
                        0.0, _kFocusProgressWhenUnfocusedFullyTransparent) /
                    _kFocusProgressWhenUnfocusedFullyTransparent) *
            255)
        .round();

    childrenSortedByFocusProgress.forEach((RenderBox child) {
      _paintChild(context, offset, child, unfocusedAlpha);
    });

    if (_scrimColor.alpha != 0) {
      if (blurScrimmedChildren) {
        context.pushBackdropFilter(
          offset,
          new ImageFilter.blur(
            sigmaX: _scrimColor.alpha * _kAlphaToBlurRatio,
            sigmaY: _scrimColor.alpha * _kAlphaToBlurRatio,
          ),
          _paintScrim,
        );
      } else {
        _paintScrim(context, offset);
      }
    }
    _paintChild(context, offset, lastChild, unfocusedAlpha);
  }

  void _paintScrim(
    PaintingContext context,
    Offset offset,
  ) {
    context.canvas.drawRect(
      new Rect.fromLTWH(offset.dx, offset.dy, size.width, size.height),
      new Paint()..color = _scrimColor,
    );
  }

  void _paintChild(
    PaintingContext context,
    Offset offset,
    RenderBox child,
    int unfocusedAlpha,
  ) {
    final StoryListRenderBlockParentData childParentData = child.parentData;
    if (unfocusedAlpha != 255 && childParentData.focusProgress == 0.0) {
      // Apply transparency.
      assert(needsCompositing);
      context.pushOpacity(
        childParentData.offset + offset,
        unfocusedAlpha,
        (PaintingContext context, Offset offset) =>
            context.paintChild(child, offset),
      );
    } else {
      context.paintChild(child, childParentData.offset + offset);
    }
  }

  @override
  bool hitTestChildren(HitTestResult result, {Point position}) {
    final List<RenderBox> children =
        _childrenSortedByFocusProgress.reversed.toList();
    if (children.isNotEmpty) {
      final RenderBox mostFocusedChild = children.first;
      final StoryListRenderBlockParentData mostFocusedChildParentData =
          mostFocusedChild.parentData;
      double mostFocusedProgress = mostFocusedChildParentData.focusProgress;

      // Only hit the most focused child if it has some progress focusing.
      // This effectively prevents all of the most focused child's siblings
      // from being tapped, dragged over, or otherwise interacted with.
      if (mostFocusedProgress > 0.0) {
        Point transformed = new Point(
          position.x - mostFocusedChildParentData.offset.dx,
          position.y - mostFocusedChildParentData.offset.dy,
        );
        if (mostFocusedChild.hitTest(result, position: transformed)) {
          return true;
        }
      } else {
        // Return the first child that passes the hit test.  Note, this doesn't
        // mean that's the only child that was hit (it's possible to hit
        // multiple children (for example a translucent child will add itself to
        // the HitTestResult but will return false for its hitTest)).
        for (int i = 0; i < children.length; i++) {
          final RenderBox child = children[i];
          final StoryListRenderBlockParentData childParentData =
              child.parentData;
          Point transformed = new Point(
            position.x - childParentData.offset.dx,
            position.y - childParentData.offset.dy,
          );
          if (child.hitTest(result, position: transformed)) {
            return true;
          }
        }
      }
    }
    return false;
  }

  @override
  void performLayout() {
    assert(!constraints.hasBoundedHeight);
    assert(constraints.hasBoundedWidth);

    double scrollOffset = _scrollController?.offset ?? 0.0;
    double maxFocusProgress = 0.0;
    double inlinePreviewScale = getInlinePreviewScale(parentSize);
    double inlinePreviewTranslateToParentCenterRatio = math.min(
      1.0,
      inlinePreviewScale * 1.5 - 0.3,
    );
    double parentCenterOffsetY = listHeight +
        (_bottomPadding - scrollOffset - (parentSize.height / 2.0));
    Point parentCenter = new Point(parentSize.width / 2.0, parentCenterOffsetY);

    {
      RenderBox child = firstChild;
      while (child != null) {
        final StoryListRenderBlockParentData childParentData = child.parentData;

        double layoutHeight = childParentData.storyLayout.size.height;
        double layoutWidth = childParentData.storyLayout.size.width;
        double layoutOffsetX = childParentData.storyLayout.offset.dx;
        double layoutOffsetY = childParentData.storyLayout.offset.dy;
        double hintScale = lerpDouble(
          1.0,
          1.25,
          childParentData.inlinePreviewHintScaleProgress,
        );
        double liftScaleMultiplier = lerpDouble(
          liftScale * hintScale,
          1.0,
          childParentData.inlinePreviewScaleProgress,
        );
        double scaledLayoutHeight = lerpDouble(
              layoutHeight,
              parentSize.height * inlinePreviewScale,
              childParentData.inlinePreviewScaleProgress,
            ) *
            liftScaleMultiplier;
        double scaledLayoutWidth = lerpDouble(
              layoutWidth,
              parentSize.width * inlinePreviewScale,
              childParentData.inlinePreviewScaleProgress,
            ) *
            liftScaleMultiplier;
        double scaleOffsetDeltaX = (layoutWidth - scaledLayoutWidth) / 2.0;
        double scaleOffsetDeltaY = (layoutHeight - scaledLayoutHeight) / 2.0;

        // Layout the child.
        double childHeight = lerpDouble(
          scaledLayoutHeight +
              InlineStoryTitle.getHeight(childParentData.focusProgress),
          parentSize.height,
          childParentData.focusProgress,
        );
        double childWidth = lerpDouble(
          scaledLayoutWidth,
          parentSize.width,
          childParentData.focusProgress,
        );
        child.layout(
          new BoxConstraints.tightFor(
            width: childWidth,
            height: childHeight,
          ),
          parentUsesSize: false,
        );
        // Position the child.
        childParentData.offset = new Offset(
          lerpDouble(
            layoutOffsetX + scaleOffsetDeltaX + constraints.maxWidth / 2.0,
            0.0,
            childParentData.focusProgress,
          ),
          lerpDouble(
            layoutOffsetY + scaleOffsetDeltaY + listHeight,
            listHeight - parentSize.height - scrollOffset + _bottomPadding,
            childParentData.focusProgress,
          ),
        );

        // Reposition toward center if inline previewing.
        Point currentCenter = new Point(
          childParentData.offset.dx + childWidth / 2.0,
          childParentData.offset.dy + childHeight / 2.0,
        );
        Offset centeringOffset = parentCenter - currentCenter;
        childParentData.offset += centeringOffset.scale(
          lerpDouble(
            0.0,
            inlinePreviewTranslateToParentCenterRatio,
            childParentData.inlinePreviewScaleProgress,
          ),
          lerpDouble(
            0.0,
            inlinePreviewTranslateToParentCenterRatio,
            childParentData.inlinePreviewScaleProgress,
          ),
        );
        maxFocusProgress = math.max(
          maxFocusProgress,
          childParentData.focusProgress,
        );

        child = childParentData.nextSibling;
      }
    }

    // If any of the children are focused or focusing, shift all
    // non-focused/non-focusing children off screen.
    if (_kSlideUnfocusedAway && maxFocusProgress > 0.0) {
      RenderBox child = firstChild;
      while (child != null) {
        final StoryListRenderBlockParentData childParentData = child.parentData;
        if (childParentData.focusProgress == 0.0) {
          childParentData.offset = childParentData.offset +
              new Offset(0.0, _kSlideUnfocusedAwayOffsetY * maxFocusProgress);
        }
        child = childParentData.nextSibling;
      }
    }

    // When we focus on a child there's a chance that the focused child will be
    // taller than the unfocused list.  In that case, increase the height of the
    // block to be that of the focusing child and shift all the children down to
    // compensate.
    double unfocusedHeight = listHeight + _bottomPadding;
    double deltaTooSmall =
        (parentSize.height * maxFocusProgress) - unfocusedHeight;
    double finalHeight = unfocusedHeight;
    if (deltaTooSmall > 0.0) {
      // shift all children down by deltaTooSmall.
      RenderBox child = firstChild;
      while (child != null) {
        final StoryListRenderBlockParentData childParentData = child.parentData;
        childParentData.offset = new Offset(
          childParentData.offset.dx,
          childParentData.offset.dy + deltaTooSmall,
        );
        child = childParentData.nextSibling;
      }

      finalHeight = (parentSize.height * maxFocusProgress);
    }

    size = constraints.constrain(
      new Size(
        constraints.maxWidth,
        finalHeight,
      ),
    );

    assert(!size.isInfinite);
  }

  List<RenderBox> get _childrenSortedByFocusProgress {
    final List<RenderBox> children = <RenderBox>[];
    RenderBox child = firstChild;
    while (child != null) {
      final BlockParentData childParentData = child.parentData;
      children.add(child);
      child = childParentData.nextSibling;
    }

    children.sort((RenderBox child1, RenderBox child2) {
      final StoryListRenderBlockParentData child1ParentData = child1.parentData;
      final StoryListRenderBlockParentData child2ParentData = child2.parentData;
      return child1ParentData.focusProgress > child2ParentData.focusProgress
          ? 1
          : child1ParentData.focusProgress < child2ParentData.focusProgress
              ? -1
              : child1ParentData.inlinePreviewScaleProgress >
                      child2ParentData.inlinePreviewScaleProgress
                  ? 1
                  : child1ParentData.inlinePreviewScaleProgress <
                          child2ParentData.inlinePreviewScaleProgress
                      ? -1
                      : 0;
    });
    return children;
  }

  static double getInlinePreviewScale(Size parentSize) =>
      ((1280.0 * 1.5 - math.max(parentSize.width, parentSize.height)) / 1280.0)
          .clamp(0.4, 0.8);
}
