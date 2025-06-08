"""
URL configuration for bluemoon project.

The `urlpatterns` list routes URLs to views. For more information please see:
    https://docs.djangoproject.com/en/5.0/topics/http/urls/
Examples:
Function views
    1. Add an import:  from my_app import views
    2. Add a URL to urlpatterns:  path('', views.home, name='home')
Class-based views
    1. Add an import:  from other_app.views import Home
    2. Add a URL to urlpatterns:  path('', Home.as_view(), name='home')
Including another URLconf
    1. Import the include() function: from django.urls import include, path
    2. Add a URL to urlpatterns:  path('blog/', include('blog.urls'))
"""
from django.contrib import admin
from django.urls import path
from django.shortcuts import render
from core.models import *  # sửa lại path import theo app của bạn
from django.utils import timezone
from django.db.models import Sum, Q, Value, Min, DecimalField
from django.db.models.functions import Coalesce
from datetime import date
from django.http import JsonResponse, HttpResponse, HttpResponseBadRequest, HttpResponseNotAllowed
from django.views.decorators.csrf import csrf_exempt
from django.views.decorators.http import require_POST
from django.shortcuts import redirect, get_object_or_404
import json
from django.db import connection
from django.shortcuts import redirect
from django.conf import settings
import stripe
from django.utils.timezone import now
import logging
from django.views.decorators.http import require_POST

stripe.api_key = settings.STRIPE_SECRET_KEY
logger = logging.getLogger(__name__)

@csrf_exempt
def cudan_view(request):
    if not request.session.get('user_id') or request.session.get('role') != 'chu_ho':
        return redirect('/login')

    user_id = request.session['user_id']
    household = Household.objects.filter(head__id=user_id).first()

    if not household:
        return render(request, 'error.html', {'message': 'Không tìm thấy thông tin hộ dân.'})

    today = date.today()

    fees = Fee.objects.filter(
        (Q(is_common=True) | Q(households=household))
    ).distinct()

    # Lấy tất cả bản ghi Payment liên quan
    all_payments = Payment.objects.filter(
        household=household,
        fee__in=fees
    )

    total_fee = fees.aggregate(
        total=Coalesce(Sum('amount'), Value(0), output_field=DecimalField())
    )['total']

    paid_total = all_payments.filter(status='paid').aggregate(
        total=Coalesce(Sum('fee__amount'), Value(0), output_field=DecimalField())
    )['total']

    unpaid_total = total_fee - paid_total if total_fee else 0

    due_date = fees.aggregate(
        soonest=Min('due_date')
    )['soonest']

    # Tạo danh sách khoản phí kèm payment.id (nếu có)
    fee_status_list = []
    for fee in fees:
        payment = all_payments.filter(fee=fee).first()
        fee_status_list.append({
            'fee_id': str(fee.id),
            'payment_id': str(payment.id) if payment else '',
            'title': fee.title,
            'amount': fee.amount,
            'status': payment.status if payment else 'unpaid'
        })

    user = User.objects.get(id=user_id)

    # Lịch sử yêu cầu
    request_history = ResidencyRequest.objects.filter(user=user).order_by('-created_at')

    # Lịch sử thanh toán (chỉ lấy payment đã paid)
    payment_history = Payment.objects.filter(household=household, status='paid').select_related('fee').order_by('-paid_at')

    return render(request, 'homeowner.html', {
        'fullname': household.head.fullname,
        'apartment_number': household.household_number,
        'total_fee': total_fee,
        'paid_total': paid_total,
        'unpaid_total': unpaid_total,
        'due_date': due_date,
        'fee_status_list': fee_status_list,
        'request_history': request_history,
        'payment_history': payment_history,
    })

@csrf_exempt
def fee_detail_api(request, fee_id):
    fee = get_object_or_404(Fee, pk=fee_id)

    if request.method == 'GET':
        return JsonResponse({
            'id': str(fee.id),
            'title': fee.title,
            'amount': fee.amount,
            'type': fee.type,
            'due_date': fee.due_date.strftime('%Y-%m-%d'),
            'description': fee.description,
        })

    elif request.method == 'PUT':
        try:
            data = json.loads(request.body)
            allowed_fields = ['title', 'amount', 'type', 'due_date', 'description']

            for field in allowed_fields:
                if field in data:
                    setattr(fee, field, data[field])
            fee.save()
            return JsonResponse({'success': True})
        except Exception as e:
            return HttpResponseBadRequest(f"Lỗi: {str(e)}")

    else:
        return HttpResponseNotAllowed(['GET', 'PUT'])

@csrf_exempt  # hoặc bạn có thể dùng CSRF token hợp lệ, không bỏ decorator nếu có token
def delete_fee(request, fee_id):
    if request.method == 'POST':
        fee = get_object_or_404(Fee, pk=fee_id)
        fee.delete()
        return JsonResponse({'message': 'Xóa khoản phí thành công'})
    else:
        return HttpResponseNotAllowed(['POST'])

@csrf_exempt
def create_checkout_session(request):
    if request.method != 'POST':
        return HttpResponseBadRequest("Invalid method")

    try:
        data = json.loads(request.body)
        payment_id = data.get('payment_id')  # frontend gửi key này

        payment = Payment.objects.get(id=payment_id)

        session = stripe.checkout.Session.create(
            payment_method_types=['card'],
            line_items=[{
                'price_data': {
                    'currency': 'usd',
                    'product_data': {
                        'name': f'Thanh toán phí: {payment.fee.title}',
                    },
                    'unit_amount': int(payment.fee.amount * 100),  # USD -> cents
                },
                'quantity': 1,
            }],
            mode='payment',
            success_url=request.build_absolute_uri('/payment-success/'),
            cancel_url=request.build_absolute_uri('/payment-cancelled/'),
            metadata={
                'payment_id': str(payment.id)
            }
        )

        return JsonResponse({'url': session.url})

    except Payment.DoesNotExist:
        return HttpResponseBadRequest("Không tìm thấy payment.")
    except Exception as e:
        logger.error(f"Error creating Stripe checkout session: {e}")
        return JsonResponse({'error': str(e)}, status=500)


@csrf_exempt
def stripe_webhook(request):
    payload = request.body
    sig_header = request.META.get('HTTP_STRIPE_SIGNATURE')
    endpoint_secret = settings.STRIPE_WEBHOOK_SECRET

    try:
        event = stripe.Webhook.construct_event(payload, sig_header, endpoint_secret)
    except ValueError as e:
        logger.error(f'Invalid payload: {e}')
        return HttpResponse(status=400)
    except stripe.error.SignatureVerificationError as e:
        logger.error(f'Signature verification failed: {e}')
        return HttpResponse(status=400)

    logger.info(f'Received Stripe event: {event["type"]}')

    if event['type'] == 'checkout.session.completed':
        session = event['data']['object']
        payment_id = session['metadata'].get('payment_id')

        logger.info(f'Checkout session completed for payment_id: {payment_id}')
        try:
            payment = Payment.objects.get(id=payment_id)
            payment.status = 'paid'
            payment.paid_at = timezone.now()
            payment.method = 'card'
            payment.save()
            logger.info(f'Payment {payment_id} updated to paid')
        except Payment.DoesNotExist:
            logger.error(f'Payment with id {payment_id} does not exist')

    return HttpResponse(status=200)

@csrf_exempt
def login_view(request):
    
    if request.method == 'GET':
        return render(request, 'dangnhap.html')

    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            username = data.get('username')
            password = data.get('password')
            role_input = data.get('role')

            role_map = {
                'resident': 'chu_ho',
                'leader': ['to_truong', 'to_pho'],
                'accountant': 'thu_ky'
            }
            allowed_roles = role_map.get(role_input)
            if isinstance(allowed_roles, str):
                allowed_roles = [allowed_roles]
            with connection.cursor() as cursor:
                cursor.execute("""
                    SELECT user_id, username, fullname, role
                    FROM users
                    WHERE username = %s
                    AND role IN %s
                    AND password_hash = crypt(%s, password_hash)
                    AND status = 'active'
                """, [username, tuple(allowed_roles), password])
                row = cursor.fetchone()

            if row:
                # ✔️ Lưu trạng thái đăng nhập
                request.session['user_id'] = str(row[0])
                request.session['username'] = row[1]
                request.session['fullname'] = row[2]
                request.session['role'] = row[3]

                return JsonResponse({
                    'success': True,
                    'redirect_url': get_redirect_url(row[3]),
                    'user': {'fullname': row[2], 'username': row[1], 'role': row[3]}
                })
            else:
                return JsonResponse({'success': False, 'message': 'Sai tài khoản, mật khẩu hoặc vai trò không hợp lệ.'})
        except Exception as e:
            return JsonResponse({'success': False, 'message': str(e)})
    return JsonResponse({'success': False, 'message': 'Chỉ hỗ trợ POST'})

def logout_view(request):
    request.session.flush()  
    return redirect('/login')

def get_redirect_url(role):
    if role == 'chu_ho':
        return '/cudan'
    elif role in ['to_truong', 'to_pho']:
        return '/leader'
    elif role == 'thu_ky':
        return '/ketoan'
    return '/login'

def payment_success(request):
    payment_id = request.session.pop('pending_payment_id', None)
    if payment_id:
        try:
            payment = Payment.objects.get(id=payment_id)
            payment.status = 'paid'
            payment.method = 'card'
            payment.paid_at = now()
            payment.save()
        except Payment.DoesNotExist:
            return render(request, 'error.html', {'message': 'Không tìm thấy bản ghi thanh toán.'})

    return render(request, 'payment_success.html')

def payment_cancel(request):
    return render(request, 'payment_cancel.html')

@csrf_exempt
@require_POST
def submit_residency_request(request):
    try:
        # Lấy user_id từ session
        user_id = request.session.get('user_id')
        if not user_id:
            return JsonResponse({"error": "Bạn chưa đăng nhập."}, status=403)
        
        # Lấy User instance từ DB (model của bạn)
        user = get_object_or_404(User, id=user_id)

        data = json.loads(request.body)

        ResidencyRequest.objects.create(
            user=user,  # Gán user của bạn
            request_type=data.get("request_type"),
            from_date=data.get("from_date"),
            to_date=data.get("to_date"),
            origin=data.get("origin"),
            destination=data.get("destination"),
            reason=data.get("reason"),
            status='pending',
            created_at=now(),
            updated_at=now()
        )
        return JsonResponse({"message": "Đã gửi yêu cầu thành công."})

    except Exception as e:
        return JsonResponse({"error": str(e)}, status=400)


urlpatterns = [
    path('login/', login_view, name='home'), 
    path('logout/', logout_view, name='logout'),  
    path('admin/', admin.site.urls),
    path('cudan/', cudan_view, name='cudan'),
    path('payment-success/', payment_success, name='payment_success'),
    path('payment-cancelled/', payment_cancel, name='payment_cancellled'),
    path('create-checkout-session/', create_checkout_session, name='create_checkout_session'),
    path('webhook/', stripe_webhook, name='stripe_webhook'),
    path("residency/submit/", submit_residency_request, name="submit_residency_request"),
    path('api/fees/<uuid:fee_id>/', fee_detail_api, name='fee_detail_api'),
    path('fees/<uuid:fee_id>/delete/', delete_fee, name='delete_fee'),
]

