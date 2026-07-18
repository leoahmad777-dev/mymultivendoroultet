<script setup>
import { ref } from 'vue'

const msg = ref('Hello World!')
</script>

<template>
  <h1>{{ msg }}</h1>
  <input v-model="msg" />
</template>
// 1. xxxx_xx_xx_create_users_table.php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up() {
        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('email')->unique();
            $table->string('password');
            $table->enum('role', ['organizer', 'cashier', 'vendor']);
            $table->timestamps();
        });
    }
};

// 2. xxxx_xx_xx_create_vendors_table.php
return new class extends Migration {
    public function up() {
        Schema::create('vendors', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->onDelete('cascade');
            $table->string('name');
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });
    }
};

// 3. xxxx_xx_xx_create_products_table.php
return new class extends Migration {
    public function up() {
        Schema::create('products', function (Blueprint $table) {
            $table->id();
            $table->foreignId('vendor_id')->constrained()->onDelete('cascade');
            $table->string('name');
            $table->decimal('price', 10, 2);
            $table->integer('stock')->default(0);
            $table->timestamps();
        });
    }
};

// 4. xxxx_xx_xx_create_transactions_table.php
return new class extends Migration {
    public function up() {
        Schema::create('transactions', function (Blueprint $table) {
            $table->id();
            $table->string('receipt_no')->unique();
            $table->foreignId('cashier_id')->constrained('users')->onDelete('cascade');
            $table->enum('payment_method', ['cash', 'qr']);
            $table->decimal('total_amount', 10, 2);
            $table->timestamps();
        });
    }
};

// 5. xxxx_xx_xx_create_transaction_items_table.php
return new class extends Migration {
    public function up() {
        Schema::create('transaction_items', function (Blueprint $table) {
            $table->id();
            $table->foreignId('transaction_id')->constrained()->onDelete('cascade');
            $table->foreignId('product_id')->constrained()->onDelete('cascade');
            $table->foreignId('vendor_id')->constrained()->onDelete('cascade'); // Diasingkan awal untuk mudahkan Settlement
            $table->integer('quantity');
            $table->decimal('unit_price', 10, 2);
            $table->decimal('subtotal', 10, 2);
            $table->timestamps();
        });
    }
};

// 6. xxxx_xx_xx_create_settlements_table.php
return new class extends Migration {
    public function up() {
        Schema::create('settlements', function (Blueprint $table) {
            $table->id();
            $table->date('date');
            $table->foreignId('vendor_id')->constrained()->onDelete('cascade');
            $table->decimal('total_sales', 10, 2)->default(0);
            $table->decimal('cash_amount', 10, 2)->default(0);
            $table->decimal('qr_amount', 10, 2)->default(0);
            $table->boolean('is_exported')->default(false);
            $table->timestamps();
        });
    }
};// app/Models/User.php
class User extends Authenticatable {
    protected $fillable = ['name', 'email', 'password', 'role'];
    
    public function vendor() {
        return $this->hasOne(Vendor::class);
    }
}

// app/Models/Vendor.php
class Vendor extends Model {
    protected $fillable = ['user_id', 'name', 'is_active'];

    public function user() {
        return $this->belongsTo(User::class);
    }
    public function products() {
        return $this->hasMany(Product::class);
    }
    public function transactionItems() {
        return $this->hasMany(TransactionItem::class);
    }
}

// app/Models/Product.php
class Product extends Model {
    protected $fillable = ['vendor_id', 'name', 'price', 'stock'];

    public function vendor() {
        return $this->belongsTo(Vendor::class);
    }
}

// app/Models/Transaction.php
class Transaction extends Model {
    protected $fillable = ['receipt_no', 'cashier_id', 'payment_method', 'total_amount'];

    public function cashier() {
        return $this->belongsTo(User::class, 'cashier_id');
    }
    public function items() {
        return $this->hasMany(TransactionItem::class);
    }
}

// app/Models/TransactionItem.php
class TransactionItem extends Model {
    protected $fillable = ['transaction_id', 'product_id', 'vendor_id', 'quantity', 'unit_price', 'subtotal'];

    public function transaction() {
        return $this->belongsTo(Transaction::class);
    }
    public function product() {
        return $this->belongsTo(Product::class);
    }
    public function vendor() {
        return $this->belongsTo(Vendor::class);
    }
}// app/Repositories/Contracts/ProductRepositoryInterface.php
namespace App\Repositories\Contracts;

interface ProductRepositoryInterface {
    public function getAllActiveWithStock();
    public function findById($id);
    public function decrementStock($id, $quantity);
}

// app/Repositories/Eloquent/ProductRepository.php
namespace App\Repositories\Eloquent;

use App\Models\Product;
use App\Repositories\Contracts\ProductRepositoryInterface;

class ProductRepository implements ProductRepositoryInterface {
    public function getAllActiveWithStock() {
        // Hanya ambil produk yang mempunyai stok lebih daripada 0
        return Product::where('stock', '>', 0)->with('vendor:id,name')->get();
    }

    public function findById($id) {
        return Product::findOrFail($id);
    }

    public function decrementStock($id, $quantity) {
        $product = $this->findById($id);
        $product->decrement('stock', $quantity);
        return $product;
    }
}// app/Repositories/Contracts/TransactionRepositoryInterface.php
namespace App\Repositories\Contracts;

interface TransactionRepositoryInterface {
    public function create(array $data);
    public function createItem(array $data);
    public function generateReceiptNumber();
}

// app/Repositories/Eloquent/TransactionRepository.php
namespace App\Repositories\Eloquent;

use App\Models\Transaction;
use App\Models\TransactionItem;
use App\Repositories\Contracts\TransactionRepositoryInterface;
use Carbon\Carbon;

class TransactionRepository implements TransactionRepositoryInterface {
    public function create(array $data) {
        return Transaction::create($data);
    }

    public function createItem(array $data) {
        return TransactionItem::create($data);
    }

    public function generateReceiptNumber() {
        // Format: REC-YYYYMMDD-XXXX (cth: REC-20260716-0001)
        $today = Carbon::today()->format('Ymd');
        $count = Transaction::whereDate('created_at', Carbon::today())->count() + 1;
        return 'REC-' . $today . '-' . str_pad($count, 4, '0', STR_PAD_LEFT);
    }
}// app/Providers/RepositoryServiceProvider.php
namespace App\Providers;

use Illuminate\Support\ServiceProvider;
use App\Repositories\Contracts\ProductRepositoryInterface;
use App\Repositories\Eloquent\ProductRepository;
use App\Repositories\Contracts\TransactionRepositoryInterface;
use App\Repositories\Eloquent\TransactionRepository;

class RepositoryServiceProvider extends ServiceProvider {
    public function register() {
        $this->app->bind(ProductRepositoryInterface::class, ProductRepository::class);
        $this->app->bind(TransactionRepositoryInterface::class, TransactionRepository::class);
    }
}// app/Services/TransactionService.php
namespace App\Services;

use App\Repositories\Contracts\TransactionRepositoryInterface;
use App\Repositories\Contracts\ProductRepositoryInterface;
use Illuminate\Support\Facades\DB;
use Exception;

class TransactionService {
    protected $transactionRepo;
    protected $productRepo;

    public function __construct(
        TransactionRepositoryInterface $transactionRepo,
        ProductRepositoryInterface $productRepo
    ) {
        $this->transactionRepo = $transactionRepo;
        $this->productRepo = $productRepo;
    }

    public function processSale(array $payload, $cashierId) {
        // Jalankan Database Transaction untuk pastikan integriti data (ACID)
        return DB::transaction(function () use ($payload, $cashierId) {
            $receiptNo = $this->transactionRepo->generateReceiptNumber();
            $totalAmount = 0;
            $itemsToSave = [];

            // 1. Semakan awal & Pengiraan Harga
            foreach ($payload['items'] as $item) {
                $product = $this->productRepo->findById($item['product_id']);

                // Semakan baki stok semasa
                if ($product->stock < $item['quantity']) {
                    throw new Exception("Stok tidak mencukupi untuk produk: {$product->name}. Baki semasa: {$product->stock}");
                }

                $subtotal = $product->price * $item['quantity'];
                $totalAmount += $subtotal;

                $itemsToSave[] = [
                    'product_id' => $product->id,
                    'vendor_id'  => $product->vendor_id,
                    'quantity'   => $item['quantity'],
                    'unit_price' => $product->price,
                    'subtotal'   => $subtotal,
                ];
            }

            // 2. Cipta Rekod Transaksi Utama
            $transaction = $this->transactionRepo->create([
                'receipt_no'     => $receiptNo,
                'cashier_id'     => $cashierId,
                'payment_method' => $payload['payment_method'],
                'total_amount'   => $totalAmount,
            ]);

            // 3. Cipta Rekod Item Jualan & Kemaskini Stok
            foreach ($itemsToSave as $itemData) {
                $itemData['transaction_id'] = $transaction->id;
                
                // Simpan item transaksi
                $this->transactionRepo->createItem($itemData);

                // Tolak stok produk
                $this->productRepo->decrementStock($itemData['product_id'], $itemData['quantity']);
            }

            return $transaction->load('items.product');
        });
    }
}// app/Http/Controllers/Api/CashierController.php
namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Repositories\Contracts\ProductRepositoryInterface;
use App\Services\TransactionService;
use Illuminate\Http\Request;
use Exception;

class CashierController extends Controller {
    protected $productRepo;
    protected $transactionService;

    public function __construct(
        ProductRepositoryInterface $productRepo,
        TransactionService $transactionService
    ) {
        $this->productRepo = $productRepo;
        $this->transactionService = $transactionService;
    }

    // Ambil senarai produk untuk carian pantas Juruwang
    public function getProducts() {
        $products = $this->productRepo->getAllActiveWithStock();
        return response()->json([
            'success' => true,
            'data'    => $products
        ]);
    }

    // Simpan transaksi jualan baharu
    public function storeTransaction(Request $request) {
        $validated = $request->validate([
            'payment_method' => 'required|in:cash,qr',
            'items'          => 'required|array|min:1',
            'items.*.product_id' => 'required|exists:products,id',
            'items.*.quantity'   => 'required|integer|min:1',
        ]);

        try {
            // Gunakan ID Juruwang yang sedang log masuk (cth: auth()->id())
            $cashierId = auth()->id() ?? 1; // Fallback ke ID 1 jika untuk mock testing
            
            $transaction = $this->transactionService->processSale($validated, $cashierId);

            return response()->json([
                'success' => true,
                'message' => 'Transaksi berjaya disimpan.',
                'data'    => $transaction
            ], 201);

        } catch (Exception $e) {
            return response()->json([
                'success' => false,
                'message' => $e->getMessage()
            ], 400);
        }
    }
}use App\Http\Controllers\Api\CashierController;

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/cashier/products', [CashierController::class, 'getProducts']);
    Route::post('/cashier/transactions', [CashierController::class, 'storeTransaction']);
});<template>
  <div class="flex h-screen bg-gray-100 font-sans">
    
    <div class="w-3/5 flex flex-col p-4">
      
      <div class="mb-4">
        <input 
          v-model="searchQuery" 
          type="text" 
          placeholder="Cari produk di sini..." 
          class="w-full p-4 text-xl rounded-lg shadow-sm border-gray-300 focus:ring-2 focus:ring-blue-500"
        />
      </div>

      <div class="flex-1 overflow-y-auto">
        <div class="grid grid-cols-2 md:grid-cols-3 gap-4 pb-20">
          <div 
            v-for="product in filteredProducts" 
            :key="product.id"
            @click="addToCart(product)"
            class="bg-white p-4 rounded-xl shadow-md cursor-pointer hover:shadow-lg transition transform hover:-translate-y-1 active:scale-95 border-l-4 border-blue-500 select-none"
          >
            <h3 class="text-lg font-bold text-gray-800 line-clamp-2 min-h-[3rem]">{{ product.name }}</h3>
            <div class="mt-2 flex justify-between items-center">
              <span class="text-xl font-extrabold text-blue-600">RM {{ product.price }}</span>
              <span class="text-sm text-gray-500 bg-gray-100 px-2 py-1 rounded">Stok: {{ product.stock }}</span>
            </div>
            <p class="text-xs text-gray-400 mt-2">{{ product.vendor.name }}</p>
          </div>
        </div>
      </div>
    </div>

    <div class="w-2/5 bg-white shadow-2xl flex flex-col relative z-10 border-l border-gray-200">
      
      <div class="p-4 bg-gray-50 border-b flex justify-between items-center">
        <h2 class="text-xl font-bold text-gray-800">Troli Semasa</h2>
        <button @click="clearCart" class="text-red-500 hover:text-red-700 font-semibold px-2 py-1 rounded">
          Kosongkan
        </button>
      </div>

      <div class="flex-1 overflow-y-auto p-4 space-y-3">
        <div v-if="cart.length === 0" class="text-center text-gray-400 mt-10">
          Belum ada produk dipilih.
        </div>

        <div 
          v-for="(item, index) in cart" 
          :key="item.product.id" 
          class="flex items-center justify-between p-3 bg-gray-50 rounded-lg border border-gray-100"
        >
          <div class="flex-1">
            <h4 class="font-bold text-gray-700">{{ item.product.name }}</h4>
            <div class="text-blue-600 font-semibold mt-1">RM {{ (item.product.price * item.quantity).toFixed(2) }}</div>
          </div>
          
          <div class="flex items-center space-x-3 bg-white p-1 rounded-md border shadow-sm">
            <button @click="decreaseQty(index)" class="w-10 h-10 flex items-center justify-center bg-gray-100 text-gray-600 rounded hover:bg-gray-200 active:bg-gray-300 text-2xl select-none">
              -
            </button>
            <span class="text-lg font-bold w-6 text-center select-none">{{ item.quantity }}</span>
            <button @click="increaseQty(index)" class="w-10 h-10 flex items-center justify-center bg-gray-100 text-gray-600 rounded hover:bg-gray-200 active:bg-gray-300 text-2xl select-none">
              +
            </button>
          </div>
        </div>
      </div>

      <div class="p-4 bg-gray-50 border-t border-gray-200">
        <div class="flex justify-between items-center mb-4">
          <span class="text-xl text-gray-600 font-semibold">Jumlah Keseluruhan</span>
          <span class="text-3xl font-extrabold text-gray-900">RM {{ cartTotal.toFixed(2) }}</span>
        </div>

        <div class="grid grid-cols-2 gap-4">
          <button 
            @click="checkout('cash')"
            :disabled="cart.length === 0 || isProcessing"
            class="py-5 bg-green-500 hover:bg-green-600 text-white rounded-xl text-2xl font-bold shadow-lg disabled:opacity-50 disabled:cursor-not-allowed transition active:scale-95 flex flex-col items-center justify-center"
          >
            <span>TUNAI</span>
          </button>
          
          <button 
            @click="checkout('qr')"
            :disabled="cart.length === 0 || isProcessing"
            class="py-5 bg-blue-600 hover:bg-blue-700 text-white rounded-xl text-2xl font-bold shadow-lg disabled:opacity-50 disabled:cursor-not-allowed transition active:scale-95 flex flex-col items-center justify-center"
          >
            <span>QR PAY</span>
          </button>
        </div>
      </div>

    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue';
import axios from 'axios';

// State
const products = ref([]);
const cart = ref([]);
const searchQuery = ref('');
const isProcessing = ref(false);

// Fetch data dari API (Rujuk Fasa 2)
const fetchProducts = async () => {
  try {
    const response = await axios.get('/api/cashier/products');
    products.value = response.data.data;
  } catch (error) {
    alert('Gagal memuat turun senarai produk.');
    console.error(error);
  }
};

onMounted(() => {
  fetchProducts();
});

// Computed: Carian Produk Pantas
const filteredProducts = computed(() => {
  if (!searchQuery.value) return products.value;
  return products.value.filter(p => 
    p.name.toLowerCase().includes(searchQuery.value.toLowerCase())
  );
});

// Computed: Pengiraan Jumlah Keseluruhan
const cartTotal = computed(() => {
  return cart.value.reduce((total, item) => {
    return total + (item.product.price * item.quantity);
  }, 0);
});

// Logik Troli
const addToCart = (product) => {
  const existingItem = cart.value.find(item => item.product.id === product.id);
  
  if (existingItem) {
    if (existingItem.quantity < product.stock) {
      existingItem.quantity++;
    } else {
      alert('Stok tidak mencukupi!');
    }
  } else {
    cart.value.push({ product, quantity: 1 });
  }
};

const increaseQty = (index) => {
  const item = cart.value[index];
  if (item.quantity < item.product.stock) {
    item.quantity++;
  }
};

const decreaseQty = (index) => {
  if (cart.value[index].quantity > 1) {
    cart.value[index].quantity--;
  } else {
    cart.value.splice(index, 1); // Buang jika kuantiti jadi 0
  }
};

const clearCart = () => {
  if(confirm('Anda pasti ingin kosongkan troli?')) {
    cart.value = [];
  }
};

// Logik Pembayaran (Menghantar ke API Laravel)
const checkout = async (method) => {
  isProcessing.value = true;
  
  // Format payload mengikut spesifikasi API Fasa 2
  const payload = {
    payment_method: method,
    items: cart.value.map(item => ({
      product_id: item.product.id,
      quantity: item.quantity
    }))
  };

  try {
    const response = await axios.post('/api/cashier/transactions', payload);
    
    if (response.data.success) {
      alert(`Transaksi Berjaya! Resit: ${response.data.data.receipt_no}`);
      cart.value = []; // Kosongkan troli untuk pelanggan seterusnya
      fetchProducts(); // Kemaskini baki stok terkini
    }
  } catch (error) {
    alert('Ralat semasa memproses pembayaran: ' + (error.response?.data?.message || error.message));
  } finally {
    isProcessing.value = false;
  }
};
</script>