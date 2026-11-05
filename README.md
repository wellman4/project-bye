<div align="center">

  # Project Bye

  A minimalist text editor designed for productive workflow and fast editing

  <div>
    <img width="600" alt="Screenshot demonstrating the pbye text editor in action" src="https://github.com/user-attachments/assets/11c3a1a7-3a4e-4431-832d-a879286bd42b" />
    <br>
    <sub>The <code>pbye</code> text editor in action</sub>
  </div>

</div>

> [!NOTE]
> Currently, tab characters (`\t`) and wide Unicode character rendering are not supported.

## 🏁 Quick start
### Prerequisites
Before getting started, ensure you have the following tools installed:
* **[Git](https://git-scm.com/):** For cloning the repository.
* **[Odin](https://odin-lang.org/):** The project is written in Odin, so you will need the compiler and its `base`, `core` and `vendor` packages which come pre-bundled with the compiler.
Follow the [Official Installation Guide](https://odin-lang.org/docs/install/).
* **[SDL3](https://libsdl.org/):** `pbye` relies on SDL3 for graphics, input, and uses the SDL3_ttf for font rendering.

### Installation & Running
#### 1. Clone the repository
First, clone the repository to your local machine and navigate into the project directory:

```bash
git clone https://github.com/wellman4/project-bye.git
cd project-bye
```

#### 2. Run the editor
Use the Odin compiler to build and run the project:

```bash
odin run src
```

#### 3. Build
To build an optimized standalone executable, run:

```bash
odin build src -vet -o:speed -out:pbye
```

## 💖 Support
If you like `pbye`, please consider [🌟 **starring** this project on GitHub](https://github.com/wellman4/project-bye/stargazers) to help it grow!

## 👤 Author
**[wellman4](https://github.com/wellman4)**