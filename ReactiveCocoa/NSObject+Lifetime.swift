import Foundation
import ReactiveSwift

private var lifetimeKey: UInt8 = 0
private var lifetimeTokenKey: UInt8 = 0

extension Reactive where Base: NSObject {
	/// Returns a lifetime that ends when the object is deallocated.
	@nonobjc public var lifetime: Lifetime {
		return base.synchronized {
			if let lifetime = objc_getAssociatedObject(base, &lifetimeKey) as! Lifetime? {
				return lifetime
			}

			let token = Lifetime.Token()
			let lifetime = Lifetime(token)

			let objcClass: AnyClass = (base as AnyObject).objcClass
			let deallocSEL = sel_registerName("dealloc")

			// Swizzle `-dealloc` so that the lifetime token is released at the
			// beginning of the deallocation chain, and only after the KVO `-dealloc`.
			objc_sync_enter(objcClass)
			if objc_getAssociatedObject(objcClass, &lifetimeKey) == nil {
				objc_setAssociatedObject(objcClass, &lifetimeKey, true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

				let existingImplRef = UnsafeMutablePointer<UnsafeMutablePointer<IMP?>?>.allocate(capacity: 1)
				existingImplRef.initialize(to: nil)

				let newImpl = _racLifetimeNewDeallocImplementation(objcClass, existingImplRef, &lifetimeTokenKey)
				assert(existingImplRef.pointee != nil)

				// If the class has no implementation of `dealloc`, the branch would not be
				// executed.
				if !class_addMethod(objcClass, deallocSEL, newImpl, "v@:") {
					// The class has an existing `dealloc`. Preserve that as `existingImpl`.
					let deallocMethod = class_getInstanceMethod(objcClass, deallocSEL)
					existingImplRef.pointee!.pointee = method_getImplementation(deallocMethod);
					existingImplRef.pointee!.pointee = method_setImplementation(deallocMethod, newImpl);
				}

				existingImplRef.deinitialize()
				existingImplRef.deallocate(capacity: 1)
			}
			objc_sync_exit(objcClass)

			objc_setAssociatedObject(base, &lifetimeTokenKey, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
			objc_setAssociatedObject(base, &lifetimeKey, lifetime, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

			return lifetime
		}
	}
}

@objc private protocol ObjCClassReporting {
	@objc(class)
	var objcClass: AnyClass { get }
}
