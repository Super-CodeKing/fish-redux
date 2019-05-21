import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../redux/redux.dart';
import '../redux_component/basic.dart';
import 'auto_dispose.dart';
import 'basic.dart';
import 'dispatch_bus.dart';

/// inter-component broadcast
mixin _InterComponent<T> on MixedStore<T> {
  final DispatchBus _bus = DispatchBus();

  @override
  void broadcastEffect(Action action, {Dispatch excluded}) =>
      _bus.broadcast(action, excluded: excluded);

  @override
  void Function() registerComponentReceiver(Dispatch dispatch) =>
      _bus.registerReceiver(dispatch);
}

/// inter-component broadcast
mixin _InterStore<T> on MixedStore<T> {
  DispatchBus _delegate;

  void setupDispatchBus(DispatchBus delegate) => _delegate = delegate;

  @override
  void broadcast(Action action, {Dispatch excluded}) =>
      _delegate?.broadcast(action, excluded: excluded);

  @override
  void Function() registerStoreReceiver(Dispatch onAction) =>
      _delegate?.registerReceiver(onAction);
}

/// build-component from store
mixin _SlotBuilder<T> on MixedStore<T> {
  @override
  Widget buildComponent(String name) =>
      slots == null ? null : slots[name]?.buildComponent(this, getState);

  Map<String, Dependent<T>> get slots;
}

/// batch notify to subscribers.
mixin _BatchNotify<T> on Store<T> {
  final List<void Function()> _listeners = <void Function()>[];
  bool _isBatching = false;
  bool _isSetupBatch = false;
  T _prevState;

  void setupBatch() {
    if (_isSetupBatch) {
      _isSetupBatch = true;
      super.subscribe(_batch);

      subscribe = (void Function() callback) {
        assert(callback != null);
        _listeners.add(callback);
        return () {
          _listeners.remove(callback);
        };
      };
    }
  }

  void _batch() {
    if (SchedulerBinding.instance?.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (!_isBatching) {
        _isBatching = true;
        SchedulerBinding.instance.addPostFrameCallback((Duration duration) {
          if (_isBatching) {
            _batch();
          }
        });
      }
    } else {
      final T curState = getState();
      if (_prevState != curState) {
        _prevState = curState;

        final List<void Function()> notifyListeners = _listeners.toList(
          growable: false,
        );
        for (void Function() listener in notifyListeners) {
          listener();
        }
        _isBatching = false;
      }
    }
  }
}

mixin _EffectEnhance<T> on MixedStore<T> implements EffectEnhancer<T> {
  EffectMiddleware<T> get effectMiddleware;

  @override
  HigherEffect<K> effectEnhance<K>(
          HigherEffect<K> higherEffect, AbstractLogic<K> logic) =>
      effectMiddleware?.call(logic, this)?.call(higherEffect) ?? higherEffect;
}

mixin _ViewEnhance<T> on MixedStore<T> implements ViewEnhancer<T> {
  ViewMiddleware<T> get viewMiddleware;

  @override
  ViewBuilder<K> viewEnhance<K>(
          ViewBuilder<K> view, AbstractComponent<K> component) =>
      viewMiddleware?.call(component, this)?.call(view) ?? view;
}

mixin _AdapterEnhance<T> on MixedStore<T> implements AdapterEnhancer<T> {
  AdapterMiddleware<T> get adapterMiddleware;

  @override
  AdapterBuilder<K> adapterEnhance<K>(
          AdapterBuilder<K> adapterBuilder, AbstractAdapter<K> adapter) =>
      adapterMiddleware?.call(adapter, this)?.call(adapterBuilder) ??
      adapterBuilder;
}

class _MixedStore<T> extends MixedStore<T>
    with
        _InterComponent<T>,
        _InterStore<T>,
        _SlotBuilder<T>,
        _BatchNotify<T>,
        _EffectEnhance<T>,
        _ViewEnhance<T>,
        _AdapterEnhance<T> {
  @override
  final Map<String, Dependent<T>> slots;
  @override
  final ViewMiddleware<T> viewMiddleware;
  @override
  final AdapterMiddleware<T> adapterMiddleware;
  @override
  final EffectMiddleware<T> effectMiddleware;

  _MixedStore(
    Store<T> store, {
    this.slots,
    this.viewMiddleware,
    this.adapterMiddleware,
    this.effectMiddleware,
    DispatchBus bus,
  }) : assert(store != null) {
    getState = store.getState;
    subscribe = store.subscribe;
    replaceReducer = store.replaceReducer;
    dispatch = store.dispatch;
    observable = store.observable;
    teardown = () {
      store.teardown();
      dispose();
    };

    setupBatch();
    setupDispatchBus(bus);
  }
}

MixedStore<T> createMixedStore<T>(
  T preloadedState,
  Reducer<T> reducer, {
  Map<String, Dependent<T>> slots,
  StoreEnhancer<T> storeEnhancer,
  ViewMiddleware<T> viewEnhancer,
  AdapterMiddleware<T> adapterMiddleware,
  EffectMiddleware<T> effectEnhancer,
  DispatchBus bus,
}) =>
    _MixedStore<T>(
      createStore(preloadedState, reducer, storeEnhancer),
      slots: slots,
      bus: bus,
      viewMiddleware: viewEnhancer,
      adapterMiddleware: adapterMiddleware,
      effectMiddleware: effectEnhancer,
    );

abstract class StoreConnector<T, K> {
  T updateT(T t, K k);
  K updateK(K k, T t);
}

/// TODO
void connectStores<T, K>(
  MixedStore<T> storeT,
  MixedStore<K> storeK,
  StoreConnector<T, K> connector,
) {
  final void Function() unsubscribeK = storeK.subscribe(() {
    final T nextT = connector.updateT(storeT.getState(), storeK.getState());
    storeT.dispatch(Action('UpdateState', payload: nextT));
  });

  final void Function() unsubscribeT = storeT.subscribe(() {
    final K nextK = connector.updateK(storeK.getState(), storeT.getState());
    storeK.dispatch(Action('UpdateState', payload: nextK));
  });

  storeT.registerOnDisposed(() {
    unsubscribeK?.call();
    unsubscribeT?.call();
  });

  storeK.registerOnDisposed(() {
    unsubscribeK?.call();
    unsubscribeT?.call();
  });
}
