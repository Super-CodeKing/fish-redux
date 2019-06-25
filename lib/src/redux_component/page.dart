import 'package:fish_redux/src/redux_component/dispatch_bus.dart';
import 'package:fish_redux/src/redux_component/enhancer.dart';
import 'package:fish_redux/src/utils/utils.dart';
import 'package:flutter/widgets.dart' hide Action;

import '../../fish_redux.dart';
import '../redux/redux.dart';
import 'basic.dart';
import 'dependencies.dart';

/// init store's state by route-params
typedef InitState<T, P> = T Function(P params);

typedef StoreUpdater<T> = Store<T> Function(Store<T> store);

@immutable
abstract class Page<T, P> extends Component<T> {
  final InitState<T, P> _initState;

  /// connect with other stores
  final List<StoreUpdater<T>> _storeUpdaters = <StoreUpdater<T>>[];

  final DispatchBus appBus = DispatchBusDefault.shared;
  final Enhancer<T> _enhancer;

  Page({
    @required InitState<T, P> initState,
    @required ViewBuilder<T> view,
    Reducer<T> reducer,
    ReducerFilter<T> filter,
    Effect<T> effect,
    HigherEffect<T> higherEffect,
    Dependencies<T> dependencies,
    ShouldUpdate<T> shouldUpdate,
    WidgetWrapper wrapper,
    Key Function(T) key,
    List<Middleware<T>> middleware,
    List<ViewMiddleware<T>> viewMiddleware,
    List<EffectMiddleware<T>> effectMiddleware,
    List<AdapterMiddleware<T>> adapterMiddleware,
  })  : assert(initState != null),
        _initState = initState,
        _enhancer = EnhancerDefault<T>(
          middleware: middleware,
          viewMiddleware: viewMiddleware,
          effectMiddleware: effectMiddleware,
          adapterMiddleware: adapterMiddleware,
        ),
        super(
          view: view,
          dependencies: dependencies,
          reducer: reducer,
          filter: filter,
          effect: effect,
          higherEffect: higherEffect,
          shouldUpdate: shouldUpdate,
          wrapper: wrapper,
          key: key,
        );

  /// Middleware
  /// TODO
  Widget buildPage(P param) => protectedWrapper(_PageWidget<T>(
        page: this,
        storeBuilder: createStoreBuilder(param),
      ));

  Get<Store<T>> createStoreBuilder(P param) =>
      () => updateStore(createBatchStore<T>(
            _initState(param),
            reducer,
            storeEnhancer: _enhancer.storeEnhance,
          ));

  Store<T> updateStore(Store<T> store) => _storeUpdaters.fold(
        store,
        (Store<T> previousValue, StoreUpdater<T> element) =>
            element(previousValue),
      );

  /// page-store connect with app-store
  void connectExtraStore<K>(
    Store<K> extraStore,

    /// To solve Reducer<Object> is neither a subtype nor a supertype of Reducer<T> issue.
    Object Function(Object, K) update,
  ) =>
      _storeUpdaters.add((Store<T> store) => connectStores<Object, K>(
            store,
            extraStore,
            update,
          ));

  bool isSuperTypeof<K>() => Tuple0<K>() is Tuple0<T>;

  bool isTypeof<K>() => Tuple0<T>() is Tuple0<K>;
}

class _PageWidget<T> extends StatefulWidget {
  final Page<T, dynamic> page;
  final Get<Store<T>> storeBuilder;

  const _PageWidget({
    Key key,
    @required this.page,
    @required this.storeBuilder,
  }) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PageState<T>();
}

class _PageState<T> extends State<_PageWidget<T>> {
  Store<T> _store;
  DispatchBus _pageBus;
  Enhancer<T> _enhancer;

  final Map<String, Object> extra = <String, Object>{};

  @override
  void initState() {
    super.initState();
    _store = widget.storeBuilder();
    _pageBus = DispatchBusDefault();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    /// Register inter-page broadcast
    _pageBus.attach(widget.page.appBus);
  }

  @override
  Widget build(BuildContext context) {
    return PageProvider(
      store: _store,
      extra: extra,
      child: widget.page.buildComponent(
        _store,
        _store.getState,
        bus: _pageBus,
        enhancer: _enhancer,
      ),
    );
  }

  @override
  void dispose() {
    _pageBus.detach();
    _store.teardown();
    super.dispose();
  }
}

class PageProvider extends InheritedWidget {
  final Store<Object> store;

  /// Used to store page data if needed
  final Map<String, Object> extra;

  const PageProvider({
    @required this.store,
    @required this.extra,
    @required Widget child,
    Key key,
  })  : assert(store != null),
        assert(child != null),
        super(key: key, child: child);

  static PageProvider tryOf(BuildContext context) {
    final PageProvider provider =
        context.inheritFromWidgetOfExactType(PageProvider);
    return provider;
  }

  @override
  bool updateShouldNotify(PageProvider oldWidget) =>
      store != oldWidget.store && extra != oldWidget.extra;
}
