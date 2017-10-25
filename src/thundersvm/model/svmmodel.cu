//
// Created by jiashuai on 17-9-21.
//

#include <thundersvm/kernel/smo_kernel.h>
#include <thrust/sort.h>
#include <thundersvm/model/svmmodel.h>
#include <thundersvm/kernel/kernelmatrix_kernel.h>

vector<real> SvmModel::predict(const DataSet::node2d &instances, int batch_size) {
    //TODO use thrust
    //prepare device data
    int n_sv = coef.size();
    SyncData<real> coef(n_sv);
    SyncData<int> sv_index(n_sv);
    SyncData<int> sv_start(1);
    SyncData<int> sv_count(1);
    SyncData<real> rho(1);

    sv_start[0] = 0;
    sv_count[0] = n_sv;
    rho[0] = this->rho;
    coef.copy_from(this->coef.data(), n_sv);
    sv_index.copy_from(this->sv_index.data(), n_sv);

    //compute kernel values
    KernelMatrix k_mat(sv, param);

    auto batch_start = instances.begin();
    auto batch_end = batch_start;
    vector<real> predict_y;
    while (batch_end != instances.end()) {
        while (batch_end != instances.end() && batch_end - batch_start < batch_size) batch_end++;
        DataSet::node2d batch_ins(batch_start, batch_end);
        SyncData<real> kernel_values(batch_ins.size() * sv.size());
        k_mat.get_rows(batch_ins, kernel_values);
        SyncData<real> dec_values(batch_ins.size());

        //sum kernel values and get decision values
        SAFE_KERNEL_LAUNCH(kernel_sum_kernel_values, kernel_values.device_data(), batch_ins.size(), sv.size(),
                           1, sv_index.device_data(), coef.device_data(), sv_start.device_data(),
                           sv_count.device_data(), rho.device_data(), dec_values.device_data());

        for (int i = 0; i < batch_ins.size(); ++i) {
            predict_y.push_back(dec_values[i]);
        }
        batch_start += batch_size;
    }
    return predict_y;
}

void SvmModel::record_model(const SyncData<real> &alpha, const SyncData<int> &y, const DataSet::node2d &instances,
                            const SvmParam param) {
    int n_sv = 0;
    for (int i = 0; i < alpha.size(); ++i) {
        if (alpha[i] != 0) {
            coef.push_back(alpha[i]);
            sv_index.push_back(sv.size());
            sv.push_back(instances[i]);
            n_sv++;
        }
    }
    this->param = param;
    LOG(INFO) << "RHO = " << rho;
    LOG(INFO) << "#SV = " << n_sv;
}

vector<real> SvmModel::cross_validation(DataSet dataset, SvmParam param, int n_fold) {
    dataset.group_classes(this->param.svm_type == SvmParam::C_SVC);//group classes only for classification

    vector<real> y_test_all;
    vector<real> y_predict_all;

    for (int k = 0; k < n_fold; ++k) {
        LOG(INFO) << n_fold << " fold cross-validation(" << k + 1 << "/" << n_fold << ")";
        DataSet::node2d x_train, x_test;
        vector<real> y_train, y_test;
        for (int i = 0; i < dataset.n_classes(); ++i) {
            int fold_test_count = dataset.count()[i] / n_fold;
            vector<int> class_idx = dataset.original_index(i);
            auto idx_begin = class_idx.begin() + fold_test_count * k;
            auto idx_end = idx_begin;
            while (idx_end != class_idx.end() && idx_end - idx_begin < fold_test_count) idx_end++;
            for (int j: vector<int>(idx_begin, idx_end)) {
                x_test.push_back(dataset.instances()[j]);
                y_test.push_back(dataset.y()[j]);
            }
            class_idx.erase(idx_begin, idx_end);
            for (int j:class_idx) {
                x_train.push_back(dataset.instances()[j]);
                y_train.push_back(dataset.y()[j]);
            }
        }
        DataSet train_dataset(x_train, dataset.n_features(), y_train);
        this->train(train_dataset, param);
        vector<real> y_predict = this->predict(x_test, 1000);
        y_test_all.insert(y_test_all.end(), y_test.begin(), y_test.end());
        y_predict_all.insert(y_predict_all.end(), y_predict.begin(), y_predict.end());
    }
    return vector<real>();
}

//real
//SvmModel::calculate_rho(const SyncData<real> &alpha, const SyncData<real> &f_val, const SyncData<int> &y,
//                        real C) const {
//    if (param.svm_type == SvmParam::C_SVC) {
//        int n_free = 0;
//        real sum_free = 0;
//        real up_value = INFINITY;
//        real low_value = -INFINITY;
//        for (int i = 0; i < alpha.size(); ++i) {
//            if (alpha[i] > 0 && alpha[i] < C) {
//                n_free++;
//                sum_free += f_val[i];
//            }
//            if (is_I_up(alpha[i], y[i], C)) up_value = min(up_value, f_val[i]);
//            if (is_I_low(alpha[i], y[i], C)) low_value = max(low_value, f_val[i]);
//        }
//        return 0 != n_free ? sum_free / n_free : -(up_value + low_value) / 2;
//    } else if (param.svm_type == SvmParam::NU_SVC) {
//        int n_free_p = 0, n_free_n = 0;
//        real sum_free_p = 0, sum_free_n = 0;
//        real up_value_p = INFINITY, up_value_n = INFINITY;
//        real low_value_p = -INFINITY, low_value_n = -INFINITY;
//        for (int i = 0; i < alpha.size(); ++i) {
//            if (y[i] > 0) {
//                if (alpha[i] > 0 && alpha[i] < C) {
//                    n_free_p++;
//                    sum_free_p += -f_val[i];
//                }
//                if (is_I_up(alpha[i], y[i], C)) up_value_p = min(up_value_p, -f_val[i]);
//                if (is_I_low(alpha[i], y[i], C)) low_value_p = max(low_value_p, -f_val[i]);
//            } else {
//                if (alpha[i] > 0 && alpha[i] < C) {
//                    n_free_n++;
//                    sum_free_n += -f_val[i];
//                }
//                if (is_I_up(alpha[i], y[i], C)) up_value_n = min(up_value_n, -f_val[i]);
//                if (is_I_low(alpha[i], y[i], C)) low_value_n = max(low_value_n, -f_val[i]);
//            }
//        }
//        real r1 = n_free_p != 0 ? sum_free_p / n_free_p : -(up_value_p + low_value_p) / 2;
//        real r2 = n_free_n != 0 ? sum_free_n / n_free_n : -(up_value_n + low_value_n) / 2;
//        return (r1 - r2) / 2;
//    }
//    //should never reach here
//    CHECK(false);
//    return 0;
//}

