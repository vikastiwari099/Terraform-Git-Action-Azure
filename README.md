# How to Deploy Azure Infrastructure Using Terraform + GitHub Actions (No Passwords, No Secrets)

This guide shows you how to connect **GitHub Actions** (which builds/deploys your
code automatically) to **Azure** (where your infrastructure actually lives),
using **Terraform** (the tool that creates the infrastructure) — all done
through the **Azure Portal**, no command-line typing needed.

We use a method called **OIDC (Workload Identity Federation)**. In simple
words: instead of storing a password/secret that GitHub uses to log into
Azure (which is risky if it ever leaks), Azure and GitHub talk to each other
directly and Azure just checks "is this really coming from GitHub Actions,
for this exact repo?" — no password ever exists anywhere.

## What's inside this project

```
terraform-azure-github-actions/
├── bootstrap/                     # One-time setup: creates a storage account to hold Terraform's memory file
│   └── main.tf
├── infra/                         # Your actual infrastructure (example)
│   ├── providers.tf
│   ├── backend.tf                 # Tells Terraform where to save its memory file
│   ├── main.tf                    # The actual Azure resources you want created
│   └── variables.tf
└── .github/workflows/
    ├── terraform-plan.yml         # Runs when you open a Pull Request -> shows a preview of changes
    ├── terraform-apply.yml        # Runs when code is merged into main -> actually creates the infrastructure
    └── terraform-destroy.yml      # Runs ONLY when you manually click a button -> deletes the infrastructure
```

Think of `terraform.tfstate` as Terraform's "memory" — a file where it keeps
track of everything it has created, so it knows what to change or delete
later. This file needs to live somewhere safe and shared — that's why we
store it in an Azure Storage Account instead of on your laptop.

---

## Step-by-step setup (all done in the Azure Portal)

### Step 1 — Create an "identity" in Azure that GitHub can use

This is like creating a special ID card that GitHub Actions will show to
Azure to prove "it's really me, let me in."

1. Go to **portal.azure.com**
2. In the top search bar, type **Microsoft Entra ID** and open it
3. In the left menu, click **App registrations**
4. Click **+ New registration**
5. Give it a name you'll recognize, e.g. `terraform-github-actions`
6. Leave everything else as default → click **Register**
7. You'll land on the app's **Overview** page. Write down these two values
   somewhere safe — you'll need them later:
   - **Application (client) ID**
   - **Directory (tenant) ID**

### Step 2 — Tell Azure to trust GitHub Actions (no password needed)

This is the important part that replaces a password entirely.

1. Still inside your new App Registration, click **Certificates & secrets**
   in the left menu
2. Click the **Federated credentials** tab
3. Click **+ Add credential**
4. Under **Federated credential scenario**, choose:
   **GitHub Actions deploying Azure resources**
5. Fill in the boxes:
   - **Organization**: your GitHub username (e.g. `vikastiwari099`)
   - **Repository**: your repo's name (e.g. `Terraform-Git-Action-Azure`)
   - **Entity type**: this decides *when* GitHub is allowed to use this ID.
     You need to add this **three separate times**, once for each of these:
     | Entity type | Value to type | Why it's needed |
     |---|---|---|
     | Pull request | *(nothing extra to type)* | So the "show me a preview" workflow can run on Pull Requests |
     | Branch | `main` | Backup, in case any workflow runs without an "environment" |
     | Environment | `production` | So the "actually build it" and "actually delete it" workflows can run |
   - **Name**: anything you'll recognize, e.g. `github-pull-requests`,
     `github-main-branch`, `github-environment-production`
6. Click **Add**
7. Repeat step 3–6 two more times so you end up with all **three** entries
   above. Missing any one of them will cause an error later that says
   something like *"no matching federated identity record found."*

> 💡 **If the form also asks for an "Organization ID" and "Repository ID"
> (numbers, not names)** — this is a newer, extra-secure version of the same
> thing. Just fill them in too if asked:
> - To find your Organization/Account ID number: open this link in your
>   browser (replace with your username):
>   `https://api.github.com/users/vikastiwari099` and look for the `"id"` value
> - To find your Repository ID number: open this link (replace with your
>   info): `https://api.github.com/repos/vikastiwari099/Terraform-Git-Action-Azure`
>   and look for the `"id"` value

#### ✅ Verified working values (from this project's actual setup)

These are the exact values confirmed to work for this repo — use this as a
reference/checklist when filling in the "Add a credential" form so you don't
mistype anything:

| Field | Value |
|---|---|
| Organization | `vikastiwari099` |
| Organization ID | `85790213` |
| Repository | `Terraform-Git-Action-Azure` |
| Repository ID | `1374439424` |
| Issuer | `https://token.actions.githubusercontent.com` |
| Audience | `api://AzureADTokenExchange` |
| Entity type | `Environment` |
| Based on selection (environment name) | `production` |
| Subject identifier *(auto-generated — do not type manually)* | `repo:vikastiwari099@85790213/Terraform-Git-Action-Azure@1374439424:environment:production` |
| Name (you choose this) | `gh-environment-production` |

> ⚠️ The **Subject identifier** box auto-fills itself once you correctly
> enter Organization, Organization ID, Repository, Repository ID, Entity
> type, and the environment name — you don't type it directly. If it doesn't
> match the row above exactly, double-check each field above it for a typo.

> ⚠️ Also remember: the **Name** field only shows placeholder/hint text by
> default (greyed out) — you must actually type a name yourself, or the
> "Update"/"Add" button won't save properly.

You'll repeat this same credential-adding process two more times for
**Pull request** and **Branch → main**, using the same Organization/Repository/
Repository ID values, just with a different Entity type each time.

### Step 3 — Give this identity permission to actually create things in Azure

Right now, this identity exists but has zero permissions — like an ID card
that doesn't open any doors yet. Let's give it access.

1. In the Azure Portal search bar, type **Subscriptions** and open it
2. Click on your subscription name
3. In the left menu, click **Access control (IAM)**
4. Click **+ Add** → **Add role assignment**
5. Search for and select **Contributor** → click **Next**
6. Under "Assign access to", choose **User, group, or service principal**
7. Click **+ Select members**, search for the name you gave your App
   Registration (e.g. `terraform-github-actions`), click it, then click
   **Select**
8. Click **Review + assign**, then **Review + assign** again to confirm

This lets it create/change/delete resources in your subscription — like
resource groups, virtual networks, etc.

### Step 4 — Create a storage account to hold Terraform's "memory" file

Terraform needs a safe place to remember what it has already built. We'll
use the `bootstrap/main.tf` file included in this project for this — it
already contains the instructions to create this storage account correctly.
Run this file **once**, from your own computer or Azure Cloud Shell (this is
the one part that does need Terraform to run once outside of GitHub — think
of it as building the shelf before you can put anything on it).

After it runs successfully, it will show you an **output** — a storage
account name. **Copy this exact name** — you'll paste it in Step 5.

> ⚠️ **Very common mistake:** don't skip this step and just type in some
> random or already-existing storage account name (like one Azure Cloud
> Shell auto-creates for itself). It must be the one this `bootstrap`
> file actually created, otherwise things fail with confusing permission
> errors later.

### Step 5 — Point Terraform to that storage account

1. Open the file `infra/backend.tf` in your repository (on GitHub.com, just
   click the file, then click the pencil ✏️ "Edit" icon)
2. Find this line:
   ```
   storage_account_name = "tfstateXXXXXX"
   ```
3. Replace `tfstateXXXXXX` with the real name you copied in Step 4
4. Click **Commit changes**

### Step 6 — Give this identity permission to actually read/write that storage account

This is a **separate, extra permission** from Step 3 — a very common thing
people forget, which causes an error called `403 AuthorizationPermissionMismatch`.

1. In the Azure Portal, search for and open your new storage account (the
   one from Step 4)
2. In the left menu, click **Access control (IAM)**
3. Click **+ Add** → **Add role assignment**
4. Search for and select **Storage Blob Data Contributor** → click **Next**
5. Under "Assign access to", choose **User, group, or service principal**
6. Search for and select the same App Registration name as before
7. Click **Review + assign** (twice)

### Step 7 — Give GitHub the three ID numbers it needs (still no password!)

1. Go to your repository on GitHub.com
2. Click **Settings** (top menu of the repo, not your account settings)
3. In the left menu, click **Secrets and variables → Actions**
4. Click **New repository secret** and add each of these three, one at a time:

   | Secret name | What to paste in |
   |---|---|
   | `AZURE_CLIENT_ID` | The "Application (client) ID" you saved in Step 1 |
   | `AZURE_TENANT_ID` | The "Directory (tenant) ID" you saved in Step 1 |
   | `AZURE_SUBSCRIPTION_ID` | Your subscription ID — find it under **Subscriptions → your subscription → Overview** in the Portal |

That's it — no password/secret value is ever stored here, just ID numbers,
which are not secret by themselves and are safe to use this way.

---

## What each workflow file actually does (in plain words)

- **`terraform-plan.yml`** — Every time you open a Pull Request, this
  automatically checks your Terraform code and shows you a **preview** of
  what would change, as a comment on the PR. Nothing is actually created yet
  — it's just a "look before you leap" step.

- **`terraform-apply.yml`** — When your code is merged into the `main`
  branch, this automatically runs and **actually creates/updates** the
  infrastructure in Azure.

- **`terraform-destroy.yml`** — This **never runs automatically**. You must
  go to the **Actions** tab on GitHub, click **Terraform Destroy**, click
  **Run workflow**, and type the word `destroy` to confirm. This is on
  purpose — deleting infrastructure should never happen by accident.

---

## Good habits to follow (explained simply)

- **Never store a password/secret for Azure login** — use the identity +
  trust method above instead (what we just set up).
- **Always keep Terraform's memory file (state) in the cloud**, not on your
  own laptop — otherwise, if your laptop dies, you lose track of everything
  Terraform built.
- **Look at the preview (`plan`) before anything is applied** — that's why
  the Pull Request workflow exists, so you review changes before they happen.
- **Only give the identity the access it actually needs** — e.g., the
  storage account only needs "Storage Blob Data Contributor," not full admin
  rights over your entire Azure account.
- **Require a human click of approval before real changes happen** — this is
  what the `environment: production` setting does; you can additionally set
  up "required reviewers" on that Environment in GitHub for extra safety.
- **Deleting things should always be a deliberate, manual action** — never
  automatic, which is why the destroy workflow requires typing `destroy` by
  hand.

---

## Common errors and what they actually mean (in plain words)

| What the error says | What it actually means | How to fix it |
|---|---|---|
| `AADSTS700213: No matching federated identity record found` | You forgot to add one of the 3 federated credential entries from Step 2 | Go back and check you have all 3: Pull request, Branch (main), Environment (production) |
| `dial tcp: no such host: tfstateXXXXXX...` | You forgot to replace the placeholder storage account name in `backend.tf` | Go to Step 5 and put in the real name |
| `403 AuthorizationPermissionMismatch` | The identity can log in, but doesn't have permission to actually read/write the storage account | Go back and do Step 6 |
| Same 403 error even after doing Step 6 | You might have given permission to the wrong storage account (double check the name matches exactly what's in `backend.tf`) | Recheck the storage account name in both places matches exactly |
| `terraform init` hangs for a really long time and then fails | The storage account's network settings are blocking outside connections | In the storage account's Portal page, go to **Networking**, and set **Public network access** to **Enabled from all networks** (fine for testing/learning; for real production setups, a more locked-down network approach is used instead) |

---

## Quick summary — the golden rule

Think of it like this: **Step 1–3 create and unlock the "ID card"** (identity
+ trust + subscription access). **Step 4–6 create the "notebook" Terraform
writes in** (storage account + permission to write in it). **Step 7 tells
GitHub which ID card to use.** If anything breaks, it's almost always because
one of these six steps was skipped, typed with a typo, or done on the wrong
resource.
