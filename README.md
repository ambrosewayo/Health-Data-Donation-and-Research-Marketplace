# Health Data Donation and Research Marketplace

A decentralized platform enabling patients to anonymously donate health data and receive cryptocurrency compensation while providing researchers verified access to medical datasets.

## Features

- **Anonymous Data Donation**: Patients submit health data with cryptographic anonymization
- **Cryptocurrency Compensation**: Donors receive STX tokens for their data contributions
- **Verified Research Access**: Researchers must be verified and pay for dataset access
- **Data Quality Rating System**: Researchers rate datasets (1-5 stars) with feedback after purchase
- **Quality-Based Discovery**: Find high-quality datasets using quality scores and ratings
- **Reputation System**: Both donors and researchers build reputation through platform usage
- **Data Marketplace**: Researchers create requests, donors fulfill them through matching
- **Platform Security**: Built-in verification, expiration, and cleanup mechanisms

## Contract Functions

### For Donors

#### `donate-health-data`
Submit anonymized health data to the marketplace.
```clarity
(contract-call? .Health_data_research donate-health-data data-hash data-type min-compensation)
```
- `data-hash`: SHA256 hash of anonymized health data
- `data-type`: Type of health data (e.g., "blood-work", "mri-scan")
- `min-compensation`: Minimum STX amount required for access

#### `deactivate-dataset`
Remove your dataset from the marketplace.
```clarity
(contract-call? .Health_data_research deactivate-dataset dataset-id)
```

#### `get-donor-dashboard`
View your donation statistics and earnings.
```clarity
(contract-call? .Health_data_research get-donor-dashboard donor-principal)
```

### For Researchers

#### `register-researcher`
Register as a researcher with institutional affiliation.
```clarity
(contract-call? .Health_data_research register-researcher "University Hospital")
```

#### `create-research-request`
Post a request for specific health data types.
```clarity
(contract-call? .Health_data_research create-research-request "blood-work" "diabetes research study" u5000000 u1440)
```
- `data-type`: Required data type
- `purpose`: Research purpose description
- `payment-amount`: STX amount willing to pay
- `duration-blocks`: Request expiration in blocks

#### `purchase-dataset-access`
Purchase access to a specific dataset.
```clarity
(contract-call? .Health_data_research purchase-dataset-access dataset-id request-id)
```

#### `rate-dataset-quality`
Rate a dataset you've purchased (1-5 stars with feedback).
```clarity
(contract-call? .Health_data_research rate-dataset-quality dataset-id u4 "High quality MRI data with clear annotations")
```

#### `get-researcher-dashboard`
View your research profile and request history.
```clarity
(contract-call? .Health_data_research get-researcher-dashboard researcher-principal)
```

### Platform Functions

#### `get-matching-datasets`
Find datasets matching specific criteria.
```clarity
(contract-call? .Health_data_research get-matching-datasets "blood-work" u10000000)
```

#### `check-dataset-eligibility`
Verify if a researcher can access a dataset.
```clarity
(contract-call? .Health_data_research check-dataset-eligibility dataset-id researcher-principal)
```

#### `get-high-quality-datasets`
Find datasets with quality scores above a threshold.
```clarity
(contract-call? .Health_data_research get-high-quality-datasets u4)
```

#### `get-dataset-quality-summary`
View quality metrics for a specific dataset.
```clarity
(contract-call? .Health_data_research get-dataset-quality-summary dataset-id)
```

#### `get-quality-rating`
View a specific researcher's rating for a dataset.
```clarity
(contract-call? .Health_data_research get-quality-rating dataset-id researcher-principal)
```

#### `get-platform-stats`
View overall platform statistics.
```clarity
(contract-call? .Health_data_research get-platform-stats)
```

## Usage Flow

### For Data Donors
1. Call `donate-health-data` with anonymized data hash and compensation requirements
2. Wait for platform verification of your dataset
3. Receive STX compensation when researchers purchase access
4. Monitor earnings through `get-donor-dashboard`

### For Researchers
1. Call `register-researcher` with institutional information
2. Wait for platform verification of researcher status
3. Call `create-research-request` specifying data needs and payment
4. Use `get-matching-datasets` or `get-high-quality-datasets` to find suitable data
5. Call `purchase-dataset-access` to buy access to specific datasets
6. Access granted datasets using the provided data hash
7. Rate dataset quality using `rate-dataset-quality` to help future researchers

## Security Features

- **Anonymization**: All patient data is hashed and anonymized
- **Verification**: Both datasets and researchers require platform approval
- **Reputation System**: Users build trust through successful transactions
- **Expiration**: Research requests automatically expire
- **Data Retention**: Old datasets are automatically cleaned up
- **Platform Fees**: 2.5% fee supports platform operations

## Testing

Run the test suite with:
```bash
clarinet test
```

Check contract syntax:
```bash
clarinet check
```

## Deployment

Deploy to testnet:
```bash
clarinet deployment generate --testnet
clarinet deployment apply --testnet
```

## Configuration

- **Platform Fee**: 2.5% (250 basis points)
- **Minimum Compensation**: 1 STX (1,000,000 microSTX)
- **Data Retention**: 144,000 blocks (~1 year)
- **Maximum Reputation**: 1,000 points

## Contract Address

Will be available after deployment to Stacks blockchain.
